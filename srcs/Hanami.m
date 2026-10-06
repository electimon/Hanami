#import "Hanami.h"
#import <Mayushii.h>
#import "HanamiClasses.h"
#import "HanamiPluginResult.h"
#import "HanamiUtils.h"
#import "HanamiEntry.h"
#import "HanamiPlugin.h"
#import "HanamiConfig.h"
#import "HanamiFileManager.h"
#import "HanamiHTTPStatusHandler.h"
#import "HanamiTemplateHandler.h"
#import "HanamiDynamicConfig.h"
#include <stdio.h>

OF_APPLICATION_DELEGATE(Hanami)

@implementation Hanami {
	OFHTTPServer *_server;
	OFMutableArray *_plugins;
	OFMutableArray *_pluginModules; // keeps OFModules (and thus dlopen handle) alive
}

#pragma mark - Macros

#define HanamiTry(x) if ((ret = x) != 0) { \
	[HanamiHTTPStatusHandler handleStatus:ret forRequest:reqCtx]; \
}

#define HanamiTryContinue(x) if ((ret = x) != HANAMI_CONTINUE) { \
	if (ret != HANAMI_SUCCESS) { \
		[HanamiHTTPStatusHandler handleStatus:ret forRequest:reqCtx]; \
		return; \
	} else { return; } \
}

#define HanamiTryAndRet(x) if ((ret = x) != 0) { \
	[HanamiHTTPStatusHandler handleStatus:ret forRequest:reqCtx]; \
	return; \
}

#pragma mark - Constants

static OFMutableDictionary *staticVarMap;

#pragma mark - Launcher

- (OFArray<MYArgOption *> *)getOptions {
	return @[
		[MYArgOption optionWithLongForm:@"--base-path" shortForm:@"-b" valueType:[OFString class] withImplictValue:@""]
	];
}

- (OFString *)parseBasePathFromArgs:(OFArray *)args {
	if (args.count <= 0) {
		OFLog(@"Hanami: Please specify base config path with -b or --base-path, even if it's just $PWD or ./");
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

	// create plugin supporting files path
	[HanamiFileManager createDirectoryAndParents:pluginsSupportPath];

	[self loadPlugins];

	// Entries
	[HanamiFileManager createDirectoryAndParents:entriesPath];

	// static files
	[HanamiFileManager createDirectoryAndParents:staticPath];
}

- (void)applicationDidFinishLaunching: (OFNotification *)notification {
	[HanamiConfig setConfigBasePath:[self parseBasePathFromArgs:[[OFApplication sharedApplication] arguments]]];
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
	staticVarMap[@"$url"] = [config valueForKey:@"url" defaultValue:[OFString stringWithFormat:@"http://%@:%d", _host, _port]];

	_server = [[OFHTTPServer alloc] init];
	_server.host = _host;
	_server.port = _port;
	_server.delegate = self;
	[_server start];
	OFLog(@"Hanami: Started HTTP server at: %@:%d, version: %@", _host, _port, VERSION);
}

#pragma mark - Delegate Methods

- (int)transformMap:(OFMutableDictionary *)varMap response:(OFHTTPResponse *)response {
	for (id<HanamiPlugin> plugin in _plugins) {
		OFLog(@"Hanami: Calling %@ to transform map", plugin);
		if (![plugin respondsToSelector:@selector(transformMap:)])
			continue; // meep, our plugin doesnt respond to this
@try {
		[plugin transformMap:varMap];
} @catch (OFException *ex) {
		OFLog(@"Encountered Exception!, plugin: %@, exception: %@", plugin, ex);
		if (tryContinueOnException.intValue == 0)
			return HTTP_STATUS_500;
		OFLog(@"try_continue_on_plugin_exception == 1, trying to continue!");
}
	}
	return HANAMI_CONTINUE;
}

- (int)tryHandleStaticFileRequest:(HanamiRequestContext *)reqCtx {
	OFArray *pathComponents = [[reqCtx.request IRI] pathComponents];
	OFString *rel = [[pathComponents objectsInRange:OFMakeRange(2, pathComponents.count - 2)] componentsJoinedByString:@"/"];
	OFIRI *iri = [HanamiUtils resolve:rel under:staticPath];
	if (iri != nil && [[OFFileManager defaultManager] fileExistsAtIRI:iri]) {
		OFData *data;
@try {
		data = [OFData dataWithContentsOfIRI:iri];
} @catch (OFException *ex) {
		return HTTP_STATUS_400;
}
		reqCtx.response.headers = @{
			@"Content-Type": [MYMimeParser mimeTypeFor:[iri pathExtension]]
		};
		[reqCtx.response writeData:data];
		return HANAMI_SUCCESS;
	}
	return HTTP_STATUS_404;
}

- (int)tryHandlePluginRoute:(HanamiRequestContext *)reqCtx {
	for (id<HanamiPlugin> plugin in _plugins) {
		if ([plugin respondsToSelector:@selector(handleRequest:)] == NO) {
			OFLog(@"Hanami: Plugin %@ cannot handle this route", [plugin name]);
			continue; // meep, our plugin doesnt respond to this
		}
		OFLog(@"Hanami: Calling %@ to handle request", [plugin name]);
		HanamiPluginResult *plugResult;
@try {
			plugResult = [plugin handleRequest:reqCtx];
} @catch (OFException *ex) {
			OFLog(@"Encountered Exception!, plugin: %@, exception: %@", [plugin name], ex);
			if ([[[HanamiConfig instanceFor:@"hanami"] valueForKey:@"try_continue_on_plugin_exception" defaultValue:@"0"] intValue] == 0) {
				[reqCtx setObject:[OFString stringWithFormat:@"Exception in plugin %@, details: %@", [plugin name], ex] forKey:@"$int_error"];
				return HTTP_STATUS_500;
			}
			OFLog(@"try_continue_on_plugin_exception == 1, trying to continue!");
}
		if (plugResult != nil && [plugResult isKindOfClass:[HanamiPluginResult class]]) {
			// we've got a handled request ^_^
			OFLog(@"Hanami: Handling with %@", [plugin name]);
			[reqCtx setStatusCode:plugResult.statusCode];
			[reqCtx setHeaders:plugResult.headers];
			// by now the plugin should written either $raw or $body, we check $raw first to handle "static" files
			if ([reqCtx objectForKey:@"$raw"] != nil)
				return [HanamiUtils writeObject:[reqCtx objectForKey:@"$raw"] toResponse:reqCtx];
			else if (plugResult.statusCode >= 300 && plugResult.statusCode < 400) { // redirection case
				reqCtx.response.headers = plugResult.headers;
				reqCtx.response.statusCode = plugResult.statusCode;
				return HANAMI_SUCCESS;
			} else {
				[HanamiUtils wrapContext:reqCtx withBody:[plugResult render:[HanamiUtils getTemplate:HTML_STORY] varMap:reqCtx.varMap]];
				return HANAMI_SUCCESS;
			}
		}
	}
	return HANAMI_CONTINUE;
}

- (void)server:(nonnull OFHTTPServer *)server didReceiveRequest:(nonnull OFHTTPRequest *)request requestBody:(nullable OFStream *)requestBody response:(nonnull OFHTTPResponse *)response {
	OFMutableDictionary *varMap = [[OFMutableDictionary alloc] initWithDictionary:staticVarMap];
	HanamiRequestContext *reqCtx = [HanamiRequestContext contextFrom:request withRequestBody:requestBody response:response andVarMap:varMap];
	int ret = 0;

	HanamiTryContinue([self transformMap:reqCtx.varMap response:reqCtx.response]);
	HanamiTryAndRet([reqCtx validateRequest]);

	OFLog(@"Hanami: Handling path: %@", reqCtx.request.IRI.path);
	OFLog(@"Hanami: Registered Plugins: %@", _plugins);

	// give plugins a chance to handle /static routes
	HanamiTryContinue([self tryHandlePluginRoute:reqCtx]);
	if (reqCtx.isStaticFileRequest) {
		HanamiTryAndRet([self tryHandleStaticFileRequest:reqCtx]);
	}

	// this case handles the root page where all posts are shown
	if ([reqCtx.request.IRI.path isEqual:@"/"]) {
		[reqCtx.response writeString:[HanamiTemplateHandler renderEntryListAtIRI:entriesPath varMap:reqCtx.varMap]];
		return;
	// this case handles subfolders/categories
	} else if ([[reqCtx.request.IRI.path pathExtension] length] < 1) {
		OFIRI *iri = [HanamiUtils resolve:reqCtx.request.IRI.path under:entriesPath];
		if (iri == nil || ![[OFFileManager defaultManager] directoryExistsAtIRI:iri]) {
			OFLog(@"IRI does not exist: %@", iri);
			[HanamiHTTPStatusHandler handleStatus:HTTP_STATUS_404 forRequest:reqCtx];
			return;
		}
		[reqCtx.response writeString:[HanamiTemplateHandler renderEntryListAtIRI:iri varMap:reqCtx.varMap]];
		return;
	// this case handles direct entry permalinks
	} else {
		OFLog(@"Handling entry: %@", reqCtx.request.IRI.path);
		if (![[reqCtx.request.IRI.path pathExtension] isEqual:defaultFlavour]) {
			[HanamiHTTPStatusHandler handleStatus:HTTP_STATUS_404 forRequest:reqCtx];
			return;
		}
		OFIRI *iri = [HanamiUtils resolve:[reqCtx.request.IRI.path stringByReplacingPathExtension:defaultFileExtension] under:entriesPath];
		if (iri == nil || ![[OFFileManager defaultManager] fileExistsAtIRI:iri]) {
			if (iri != nil)
				OFLog(@"No file found at: %@", iri);
			[HanamiHTTPStatusHandler handleStatus:HTTP_STATUS_404 forRequest:reqCtx];
			return;
		}
		iri = [iri IRIByReplacingPathExtension:defaultFileExtension];
		HanamiEntry *entry = [[HanamiEntry alloc] initWithIRI:iri relativePath:[HanamiUtils relativePathFrom:entriesPath to:iri]];
		if (entry)
			[HanamiUtils wrapContext:reqCtx withBody:[entry render:[HanamiUtils getTemplate:HTML_STORY] varMap:reqCtx.varMap]];
		else
			[HanamiHTTPStatusHandler handleStatus:HTTP_STATUS_404 forRequest:reqCtx];
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
