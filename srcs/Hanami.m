#import "Hanami.h"
#import <MYArgParser.h>
#import "HanamiPluginResult.h"
#import "HanamiUtils.h"
#import "HanamiEntry.h"
#import "HanamiPlugin.h"
#import "HanamiConfig.h"
#import "HanamiFileManager.h"
#import "HanamiHTTPStatusHandler.h"
#import "HanamiTemplateHandler.h"
#import "HanamiPrivateConfig.h"
#include <stdio.h>

OF_APPLICATION_DELEGATE(Hanami)

@implementation Hanami {
	OFHTTPServer *_server;
	OFMutableArray *_plugins;
	OFMutableArray *_pluginModules; // keeps HanamiModule (and thus dlopen handle) alive
}

#pragma mark - Constants

static OFMutableDictionary *staticVarMap;

#pragma mark - Launcher

- (OFArray<MYArgOption *> *)getOptions {
	return @[
		[MYArgOption optionWithLongForm:@"--config" shortForm:@"-c" valueType:[OFString class] withImplictValue:@""]
	];
}

- (OFString *)parseConfigPathFromArgs:(OFArray *)args {
	if (args.count <= 0) {
		OFLog(@"Hanami: Please specify base config path with -c or --config, even if it's just $PWD or ./");
		[OFApplication terminateWithStatus:1];
	}
	MYArgParser *parser = [MYArgParser parserWithOptions:[self getOptions]];
	MYArgMatch *configPathMatch = [[parser getMatches:args] objectAtIndex:0];
	return configPathMatch.value;
}

- (void)bootstrapRuntimeRequirements:(HanamiConfig *)config {
	// Plugins
	[HanamiFileManager createDirectoryAndParents:pluginsPath];
	_plugins = [[OFMutableArray alloc] init];
	_pluginModules = [[OFMutableArray alloc] init];

	// create state dir
	[HanamiFileManager createDirectoryAndParents:statePath];

	[self loadPlugins];

	// Entries
	[HanamiFileManager createDirectoryAndParents:entriesPath];

	// static files
	[HanamiFileManager createDirectoryAndParents:staticPath];
}

- (void)applicationDidFinishLaunching: (OFNotification *)notification {
	[HanamiConfig setConfigBasePath:[self parseConfigPathFromArgs:[[OFApplication sharedApplication] arguments]]];
	HanamiConfig *config = [HanamiConfig instanceFor:@"hanami"];
	[self bootstrapRuntimeRequirements:config];

	// host n port
	OFString *_host = [config valueForKey:@"host" defaultValue:@"127.0.0.1"];
	int _port = [[config valueForKey:@"port" defaultValue:@"8999"] intValue];

	// static var map, global constants
	staticVarMap = [[OFMutableDictionary alloc] init];
	staticVarMap[@"$content_type"] = HTMLContentType;
	staticVarMap[@"$blog_title"] = [config valueForKey:@"blog_title" defaultValue:@"My Weblog!"];
	staticVarMap[@"$blog_description"] = [config valueForKey:@"blog_description" defaultValue:@"rwar"];
	staticVarMap[@"$url"] = [OFString stringWithFormat:@"http://%@:%d", _host, _port];

	_server = [[OFHTTPServer alloc] init];
	_server.host = _host;
	_server.port = _port;
	_server.delegate = self;
	[_server start];
	OFLog(@"Hanami: Started HTTP server at: %@:%d, version: %@", _host, _port, VERSION);
}

#pragma mark - Delegate Methods

- (BOOL)validateRequest:(OFHTTPRequest *)request varMap:(OFMutableDictionary *)varMap response:(nonnull OFHTTPResponse *)response {
	OFArray *pathComponents;
	OFString *path;
@try {
	pathComponents = [[request IRI] pathComponents];
	path = [[request IRI] path].pathExtension;
} @catch (OFException *ex) {
	return NO;
}

	for (OFString *comp in pathComponents)
		if ([comp isEqual:@".."] || [comp containsString:@"\\"]) {
			[HanamiHTTPStatusHandler handleStatus:HTTP_STATUS_400 response:response andVarMap:varMap];
			return NO; // should be bail
		}

	return YES;
}

- (BOOL)isRequestStaticFile:(OFHTTPRequest *)request {
	OFArray *pathComponents = [[request IRI] pathComponents];
	if ([pathComponents count] > 1 && [[pathComponents objectAtIndex:1] isEqual:@"static"]) return YES; else return NO;
}

- (void)server:(nonnull OFHTTPServer *)server didReceiveRequest:(nonnull OFHTTPRequest *)request requestBody:(nullable OFStream *)requestBody response:(nonnull OFHTTPResponse *)response {
	OFMutableDictionary *varMap = [[OFMutableDictionary alloc] initWithDictionary:staticVarMap];
	OFData *requestData;

	if (![self validateRequest:request varMap:varMap response:response])
		return;

	OFArray *pathComponents = [[request IRI] pathComponents];

	response.statusCode = 200;
	response.headers = @{
		@"Content-Type": [varMap valueForKey:@"$content_type"]
	};

	if (requestBody != nil && ![self isRequestStaticFile:request]) { // static file gets shouldnt have us parsing their shit
@try {
		requestData = [requestBody readDataUntilEndOfStream];
} @catch (OFException *ex) {
		[HanamiHTTPStatusHandler handleStatus:HTTP_STATUS_400 response:response andVarMap:varMap]; return;
}
	}

	// fill in some info that could be useful for widgets like request ip
	[varMap setValue:OFSocketAddressString(request.remoteAddress) forKey:@"$request::address"];
	[varMap setValue:request.IRI.path forKey:@"$request::path"];

	OFLog(@"Hanami: Registered Plugins: %@", _plugins);

	for (id<HanamiPlugin> plugin in _plugins) {
		OFLog(@"Hanami: Calling %@ to transform map", plugin);
@try {
		[plugin transformMap:varMap];
} @catch (OFException *ex) {
		OFLog(@"Encountered Exception!, plugin: %@, exception: %@", plugin, ex);
		if (![[[HanamiConfig instanceFor:@"hanami"] valueForKey:@"try_continue_on_plugin_exception" defaultValue:@"0"] intValue]) {
			[HanamiHTTPStatusHandler handleStatus:HTTP_STATUS_500 response:response andVarMap:varMap]; return;
		}
		OFLog(@"try_continue_on_plugin_exception == 1, trying to continue!");
}
	}

	if ([self isRequestStaticFile:request]) {
		OFString *rel = [[pathComponents objectsInRange:OFMakeRange(2, pathComponents.count - 2)] componentsJoinedByString:@"/"];
		OFIRI *iri = [HanamiUtils resolve:rel under:staticPath];
		if (iri != nil && [[OFFileManager defaultManager] fileExistsAtIRI:iri]) {
			OFData *data;
@try {
			data = [OFData dataWithContentsOfIRI:iri];
} @catch (OFException *ex) {
			[HanamiHTTPStatusHandler handleStatus:HTTP_STATUS_400 response:response andVarMap:varMap]; return;
}
			[response writeData:data]; return;
		} else {
			[HanamiHTTPStatusHandler handleStatus:HTTP_STATUS_404 response:response andVarMap:varMap]; return;
		}
	}

	for (id<HanamiPlugin> plugin in _plugins) {
		if (![plugin respondsToSelector:@selector(handleRequest:requestData:andVarMap:)])
			continue; // meep, our plugin doesnt respond to this
		OFLog(@"Hanami: Calling %@ to handle request", plugin);
		HanamiPluginResult *plugResult;
@try {
			plugResult = [plugin handleRequest:request requestData:requestData andVarMap:varMap];
} @catch (OFException *ex) {
			OFLog(@"Encountered Exception!, plugin: %@, exception: %@", plugin, ex);
			if (![[[HanamiConfig instanceFor:@"hanami"] valueForKey:@"try_continue_on_plugin_exception" defaultValue:@"0"] intValue]) {
				[varMap setObject:[OFString stringWithFormat:@"Exception in plugin %@, details: %@", plugin, ex] forKey:@"$int_error"];
				[HanamiHTTPStatusHandler handleStatus:HTTP_STATUS_500 response:response andVarMap:varMap]; return;
			}
			OFLog(@"try_continue_on_plugin_exception == 1, trying to continue!");
}
		if (plugResult != nil && [plugResult isKindOfClass:[HanamiPluginResult class]]) {
			// we've got a handled request ^_^
			OFLog(@"Hanami: Handling with %@", plugin);
			response.statusCode = plugResult.statusCode;
			response.headers = plugResult.headers;
			// by now the plugin should written either $raw or $body, we check $raw first to handle "static" files
@try {
			if ([varMap objectForKey:@"$raw"]) {
				if ([[varMap objectForKey:@"$raw"] isKindOfClass:[OFData class]])
					[response writeData:[varMap objectForKey:@"$raw"]];
				else if ([[varMap objectForKey:@"$raw"] isKindOfClass:[OFString class]])
					[response writeString:[varMap objectForKey:@"$raw"]];
				else
					OFLog(@"Hanami: Plugin %@ set $raw, but we don't know how to handle it! $raw: ", plugin, [[varMap objectForKey:@"$raw"] class]);
			} else
				[HanamiUtils wrapResponse:response withBody:[plugResult render:[HanamiUtils getTemplate:HTML_STORY] varMap:varMap] andVarMap:varMap];
			return;
}
@catch (OFException *ex) {
			OFLog(@"Encountered Exception!, plugin: %@, exception: %@", plugin, ex);
			[varMap setObject:[OFString stringWithFormat:@"Exception in plugin %@, details: %@", plugin, ex] forKey:@"$int_error"];
			[HanamiHTTPStatusHandler handleStatus:HTTP_STATUS_500 response:response andVarMap:varMap]; return;
}
		}
	}

	// this case handles the root page where all posts are shown
	if ([request.IRI.path isEqual:@"/"]) {
		[response writeString:[HanamiTemplateHandler renderEntryListAtIRI:entriesPath varMap:varMap]];
		return;
	// this case handles subfolders/categories
	} else if ([[request.IRI.path pathExtension] length] < 1) {
		OFIRI *iri = [HanamiUtils resolve:request.IRI.path under:entriesPath];
		if (iri == nil || ![[OFFileManager defaultManager] directoryExistsAtIRI:iri]) {
			OFLog(@"IRI does not exist: %@", iri);
			[HanamiHTTPStatusHandler handleStatus:HTTP_STATUS_404 response:response andVarMap:varMap]; return;
		}
		[response writeString:[HanamiTemplateHandler renderEntryListAtIRI:iri varMap:varMap]];
		return;
	// this case handles direct entry permalinks
	} else {
		OFLog(@"Handling entry: %@", request.IRI.path);
		if (![[request.IRI.path pathExtension] isEqual:defaultFlavour]) {
			[HanamiHTTPStatusHandler handleStatus:HTTP_STATUS_404 response:response andVarMap:varMap]; return;
		}
		// would do stringByReplacingString but if you have say aaaahtmlaaaa.html and we do it youll get aaaatxtaaaa.txt
		OFIRI *iri = [HanamiUtils resolve:[[request.IRI.path stringByDeletingPathExtension] stringByAppendingPathExtension:defaultFileExtension] under:entriesPath];
		if (iri == nil || ![[OFFileManager defaultManager] fileExistsAtIRI:iri]) {
			if (iri != nil)
				OFLog(@"No file found at: %@", iri);
			[HanamiHTTPStatusHandler handleStatus:HTTP_STATUS_404 response:response andVarMap:varMap]; return;
		}
		iri = [[iri IRIByDeletingPathExtension] IRIByAppendingPathExtension:defaultFileExtension]; // todo change this to configurable option
		HanamiEntry *entry = [[HanamiEntry alloc] initWithIRI:iri relativePath:[HanamiUtils relativePathFrom:entriesPath to:iri]];
		if (entry)
			[HanamiUtils wrapResponse:response withBody:[entry render:[HanamiUtils getTemplate:HTML_STORY] varMap:varMap] andVarMap:varMap];
		else
			[HanamiHTTPStatusHandler handleStatus:HTTP_STATUS_404 response:response andVarMap:varMap];
	}
}

#pragma mark - Plugins

- (void)loadPlugins {
	// the idea is init.d style, 01, 02, 03 is the order
	for (OFIRI *file in [[[OFFileManager defaultManager] contentsOfDirectoryAtIRI:pluginsPath] sortedArrayUsingComparator:^OFComparisonResult(id  _Nonnull left, id  _Nonnull right){
        OFIRI *_left = left;
		OFIRI *_right = right;
		int leftHand, rightHand;
@try {
#ifdef OF_WINDOWS
		leftHand = [[[_left lastPathComponent] substringToIndex:2] intValue];
		rightHand = [[[_right lastPathComponent] substringToIndex:2] intValue];
#else
		leftHand = [[[_left lastPathComponent] substringWithRange:OFMakeRange(3, 2)] intValue];
		rightHand = [[[_right lastPathComponent] substringWithRange:OFMakeRange(3, 2)] intValue];
#endif
} @catch (OFInvalidFormatException *ex) {
// seems that this plugin isn't using the expected filename, we will scream while trying our best
		OFLog(@"Hanami: Could not compare plugins %@ and %@, are they labeled correctly? Trodding along...", _left, _right);
		return OFOrderedAscending;
}
        if (leftHand < rightHand)
			return OFOrderedDescending;
		else if (leftHand > rightHand)
			return OFOrderedAscending;
		return OFOrderedSame;
	} options:OFArraySortDescending]) {
		id<HanamiPlugin> plug = [self loadPlugin:[file fileSystemRepresentation]];
		if (plug)
			[_plugins addObject:plug];
	}
}

- (id<HanamiPlugin>)loadPlugin:(OFString *)plugin {
	OFModule *mod;
@try {
	mod = [OFModule moduleWithPath:plugin];
} @catch (OFException *) {
	OFLog(@"Hanami: Failed to load plugin from path %@, trodding along...", plugin);
	return nil;
}
	if (mod == nil)
		return nil; // failed to load the plugin for some reason, for now we dont handle this case

	Class (*getClass)(void) = (Class(*)(void))[mod addressForSymbol:@"HanamiPluginClass"];
	if (getClass != NULL) {
		Class cls = getClass();
		OFLog(@"Hanami: Got plugin class: %@", cls);
		id<HanamiPlugin> pluginObj = (id<HanamiPlugin>)[[cls alloc] init];
		// keep the module (and its dlopen handle) alive as long as
		// pluginObj exists, or its class metadata gets unmapped
		// need 2 find a way to remove this, it crashes without it
		[_pluginModules addObject:mod];
		return pluginObj;
	}
	return nil; // no plugin found for this path
}
@end
