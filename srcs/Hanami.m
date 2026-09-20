#import "Hanami.h"
#import <MYArgParser.h>
#include "HanamiPluginResult.h"
#import "HanamiUtils.h"
#import "HanamiEntry.h"
#import "HanamiPlugin.h"
#import "HanamiConfig.h"
#import "HanamiFileManager.h"
#include <stdio.h>

OF_APPLICATION_DELEGATE(Hanami)

@implementation Hanami {
	OFIRI *_entriesPath;
	OFIRI *_staticPath;
	OFIRI *_pluginsPath;
	OFArray *_excluded;
}

#pragma mark - My Remarks

/*
	I'd like to add a helper class that wraps an array and does nil checking on addObject, itd be nice to remove that shit from the code


*/

#pragma mark - Constants

static const OFString *HTMLContentType = @"text/html; charset=UTF-8";

static const OFString *HTMLHead = @"<!DOCTYPE html PUBLIC \"-//W3C//DTD HTML 4.01 Transitional//EN\" \"http://www.w3.org/TR/html4/loose.dtd\">\n"
"<html>\n"
"    <head>\n"
"        <meta http-equiv=\"content-type\" content=\"$content_type\" >\n"
"        <link rel=\"alternate\" type=\"application/rss+xml\" title=\"RSS\" href=\"$url/index.rss\" >\n"
"        <title>$blog_title $path_info_da $path_info_mo $path_info_yr</title>\n"
"    </head>\n"
"    <body>\n"
"        <div align=\"center\">\n"
"            <h1>$blog_title</h1>\n"
"            <p>$path_info_da $path_info_mo $path_info_yr</p>\n"
"        </div>\n";

static const OFString *HTMLStory = @"        <div>\n"
"            <h3><a name=\"$fn\">$title</a></h3>\n"
"            <div>$body</div>\n"
"            <p>posted at: $ti | path: <a href=\"$url$path\">$path</a> | <a href=\"$url/$yr/$mo_num/$da#$fn\">permanent link to this entry</a></p>\n"
"        </div>\n";

static const OFString *HTMLFoot = @"        <div align=\"center\">\n"
"            <a href=\"http://blosxom.sourceforge.net/\"><img src=\"http://blosxom.sourceforge.net/images/pb_blosxom.gif\" alt=\"powered by blosxom\" border=\"0\" width=\"90\" height=\"33\" ></a>\n"
"        </div>\n"
"    </body>\n"
"</html>\n";

static const OFString *HTMLStatus = @"		<div>\n"
"            <h3>Hanami has encountered an error...</h3>\n"
"            <div>Status: $status_code, Error: $error</div>\n"
"        </div>\n";

typedef enum {
	HTML_HEAD = 0,
	HTML_STORY,
	HTML_FOOT
} html_type_t;

typedef enum {
	HTTP_STATUS_400 = 0,	// RFC9110, Bad Request
	HTTP_STATUS_401,		// RFC9110, Unauthorized
	HTTP_STATUS_403,		// RFC9110, Forbidden
	HTTP_STATUS_404,		// RFC9110, Not Found
	HTTP_STATUS_405 = 5,	// RFC9110, Method not Allowed
	HTTP_STATUS_410 = 10,	// RFC9110, Gone
} html_client_error_t;

typedef enum {
	HTTP_STATUS_500 = 0,	// RFC9110, Internal Server Error
} html_server_error_t;

typedef enum {
	HTTP_CLIENT_ERROR_STATUS = 0,
	HTTP_SERVER_ERROR_STATUS
} html_error_type_t;

static OFMutableDictionary *staticVarMap;

#pragma mark - Dynamics xd
// should not have this section at all tbh, and have config be typed but we aint there yet

static BOOL wrapStatusPages = NO;
static BOOL tryContinueOnPluginException = NO;

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
	_pluginsPath = [HanamiFileManager IRIWithPath:[config valueForKey:@"plugin_dir" defaultValue:@"plugins"]];
	[HanamiFileManager createDirectoryAndParents:_pluginsPath];
	_plugins = [[OFMutableArray alloc] init];
	_pluginModules = [[OFMutableArray alloc] init];

	// create state dir
	OFIRI *statePath = [HanamiFileManager IRIWithPath:[config valueForKey:@"state_dir" defaultValue:@"state"]];
	[HanamiFileManager createDirectoryAndParents:statePath];

	[self loadPlugins];

	// Entries
	_entriesPath = [HanamiFileManager IRIWithPath:[config valueForKey:@"entries_dir" defaultValue:@"entries"]];
	[HanamiFileManager createDirectoryAndParents:_entriesPath];

	// static files
	_staticPath = [HanamiFileManager IRIWithPath:[config valueForKey:@"static_dir" defaultValue:@"static"]];
	[HanamiFileManager createDirectoryAndParents:_staticPath];

	// configs path
	// OFIRI *configsPath = [HanamiFileManager IRIWithPath:[config valueForKey:@"static_dir" defaultValue:@"static"]];
	// [HanamiFileManager createDirectoryAndParents:configsPath];

	// exclusions
	OFString *exclusions = [config valueForKey:@"exclude" defaultValue:@""];
	if (exclusions != nil)
		_excluded = [exclusions componentsSeparatedByString:@" "];
	else
		_excluded = [[OFArray alloc] init];

	// misc settings
	wrapStatusPages = [[config valueForKey:@"wrap_status_pages" defaultValue:@"1"] intValue];
	tryContinueOnPluginException = [[config valueForKey:@"try_continue_on_plugin_exception" defaultValue:@"0"] intValue];
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

// u may be asking, why? well i tried goto and it fucking killed my app, random crashes, thanks clang
#define bail {\
@try { \
	[response writeString:[HanamiUtils transformTemplate:[OFString stringWithFormat:@"%@%@%@", [self getTemplate:HTML_HEAD], [self getTemplate:HTML_STORY], [self getTemplate:HTML_FOOT]] varMap:varMap]]; \
} @catch (OFException *ex) { OFLog(@"%@", ex);} \
return; }

- (void)wrapResponse:(OFHTTPResponse *)response withBody:(id)story andVarMap:(OFMutableDictionary *)varMap {
	[response writeString:[HanamiUtils transformTemplate:[self getTemplate:HTML_HEAD] varMap:varMap]];
	if ([story isKindOfClass:[OFString class]])
		[response writeString:story];
	else
		[story render:[self getTemplate:HTML_STORY] varMap:varMap];
	[response writeString:[HanamiUtils transformTemplate:[self getTemplate:HTML_FOOT] varMap:varMap]];
}

- (void)server:(nonnull OFHTTPServer *)server didReceiveRequest:(nonnull OFHTTPRequest *)request requestBody:(nullable OFStream *)requestBody response:(nonnull OFHTTPResponse *)response {
	OFMutableDictionary *varMap = [[OFMutableDictionary alloc] initWithDictionary:staticVarMap];
	OFArray *pathComponents = request.IRI.pathComponents;

	for (OFString *comp in pathComponents)
		if ([comp isEqual:@".."] || [comp containsString:@"\\"]) {
			[varMap setObject:@"Detected path traversal attempt!" forKey:@"$error"];
			[self writeClientErrorPage:HTTP_CLIENT_ERROR_STATUS statusCode:HTTP_STATUS_400 response:response andVarMap:varMap];
			return; // should be bail
		}

	if ([pathComponents count] > 1 && [[pathComponents objectAtIndex:1] isEqual:@"static"]) {
		OFString *rel = [[pathComponents objectsInRange:OFMakeRange(2, pathComponents.count - 2)] componentsJoinedByString:@"/"];
		OFIRI *iri = [HanamiUtils resolve:rel under:_staticPath];
		if (iri == nil) return; // todo add 404 // should be bail
		if ([[OFFileManager defaultManager] fileExistsAtIRI:iri])
			[response writeData:[OFData dataWithContentsOfIRI:iri]];
		else {
			[varMap setObject:@"File not found." forKey:@"$error"];
			[self writeClientErrorPage:HTTP_CLIENT_ERROR_STATUS statusCode:HTTP_STATUS_404 response:response andVarMap:varMap];
		}
		
		return;
	}

	OFData *requestData;
	if (requestBody != nil)
		requestData = [requestBody readDataUntilEndOfStream];

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
		if (!tryContinueOnPluginException) {
			[varMap setObject:[OFString stringWithFormat:@"Exception in plugin %@, details: %@", plugin, ex] forKey:@"$error"];
			[self writeClientErrorPage:HTTP_SERVER_ERROR_STATUS statusCode:HTTP_STATUS_500 response:response andVarMap:varMap];
			return;
		}
		OFLog(@"try_continue_on_plugin_exception == 1, trying to continue!");
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
			if (!tryContinueOnPluginException) {
				[varMap setObject:[OFString stringWithFormat:@"Exception in plugin %@, details: %@", plugin, ex] forKey:@"$error"];
				[self writeClientErrorPage:HTTP_SERVER_ERROR_STATUS statusCode:HTTP_STATUS_500 response:response andVarMap:varMap];
				return;
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
				[self wrapResponse:response withBody:[plugResult render:[self getTemplate:HTML_STORY] varMap:varMap] andVarMap:varMap];
			return;
}
@catch (OFException *ex) {
			OFLog(@"Encountered Exception!, plugin: %@, exception: %@", plugin, ex);
			[varMap setObject:[OFString stringWithFormat:@"Exception in plugin %@, details: %@", plugin, ex] forKey:@"$error"];
			[self writeClientErrorPage:HTTP_SERVER_ERROR_STATUS statusCode:HTTP_STATUS_500 response:response andVarMap:varMap];
			return;
}
		}
	}

	response.statusCode = 200;
	response.headers = @{
		@"Content-Type": (OFString *)HTMLContentType
	};

	// this case handles the root page where all posts are shown
	if ([request.IRI.path isEqual:@"/"]) {
		[response writeString:[self renderEntryListAtIRI:_entriesPath varMap:varMap]];
		return;
	// this case handles subfolders/categories
	} else if ([[request.IRI.path pathExtension] length] < 1) {
		OFIRI *iri = [HanamiUtils resolve:request.IRI.path under:_entriesPath];
		if (iri == nil) bail; // todo add 404
		if (![[OFFileManager defaultManager] directoryExistsAtIRI:iri]) {
			OFLog(@"IRI does not exist: %@", iri);
			bail; // todo add 404
		}
		[response writeString:[self renderEntryListAtIRI:iri varMap:varMap]];
		return;
	// this case handles direct entry permalinks
	} else {
		OFLog(@"Handling entry: %@", request.IRI.path);
		OFIRI *iri = [HanamiUtils resolve:request.IRI.path under:_entriesPath];
		if (iri == nil) bail; // todo add 404
		iri = [[iri IRIByDeletingPathExtension] IRIByAppendingPathExtension:@"txt"]; // todo change this to configurable option
		HanamiEntry *entry = [[HanamiEntry alloc] initWithIRI:iri relativePath:[HanamiUtils relativePathFrom:_entriesPath to:iri]];
		if (entry)
			[self wrapResponse:response withBody:[entry render:[self getTemplate:HTML_STORY] varMap:varMap] andVarMap:varMap];
		else {
			[varMap setObject:@"File not found." forKey:@"$error"];
			[self writeClientErrorPage:HTTP_CLIENT_ERROR_STATUS statusCode:HTTP_STATUS_404 response:response andVarMap:varMap];
		}
	}
}

#pragma mark - Plugins

- (void)loadPlugins {
	// the idea is init.d style, 01, 02, 03 is the order
	// the worst code in this program by far, idk how to do it not like this i fear
	// works with both windows and linux though..
	for (OFIRI *file in [[[OFFileManager defaultManager] contentsOfDirectoryAtIRI:_pluginsPath] sortedArrayUsingComparator:^OFComparisonResult(id  _Nonnull left, id  _Nonnull right){
        OFIRI *_left = left;
		OFIRI *_right = right;
#ifdef OF_WINDOWS
        if ([[[_left lastPathComponent] substringToIndex:2] intValue] < [[[_right lastPathComponent] substringToIndex:2] intValue])
#else
        if ([[[_left lastPathComponent] substringWithRange:OFMakeRange(3, 2)] intValue] < [[[_right lastPathComponent] substringWithRange:OFMakeRange(3, 2)] intValue])
#endif
			return OFOrderedDescending;
		return OFOrderedAscending;
	} options:OFArraySortDescending]) {
		id<HanamiPlugin> plug = [self loadPlugin:[file fileSystemRepresentation]];
		if (plug)
			[_plugins addObject:plug];
	}
}

- (id<HanamiPlugin>)loadPlugin:(OFString *)plugin {
	OFModule *mod = [OFModule moduleWithPath:plugin];
	if (mod == nil)
		return nil; // failed to load the plugin for some reason, for now we dont handle this case

	Class (*getClass)(void) = (Class(*)(void))[mod addressForSymbol:@"HanamiPluginClass"];
	if (getClass != NULL) {
		Class cls = getClass();
		OFLog(@"Got class: %@", cls);
		id<HanamiPlugin> pluginObj = (id<HanamiPlugin>)[[cls alloc] init];
		// keep the module (and its dlopen handle) alive as long as
		// pluginObj exists, or its class metadata gets unmapped
		// need 2 find a way to remove this, it crashes without it
		[_pluginModules addObject:mod];
		return pluginObj;
	}
	return nil; // no plugin found for this path
}

#pragma mark - Entries

- (OFArray *)getEntriesAtIRI:(nonnull OFIRI *)iri {
	OFMutableArray *out = [[OFMutableArray alloc] init];
	OFArray *contents = [[OFFileManager defaultManager] contentsOfDirectoryAtIRI:iri];
	for (OFIRI *entryIRI in contents)
		if ([[OFFileManager defaultManager] directoryExistsAtIRI:entryIRI])
			[out addObjectsFromArray:[self getEntriesAtIRI:entryIRI]];
		else if (_excluded != nil && [_excluded containsObject:[HanamiUtils relativePathFrom:_entriesPath to:entryIRI]])
			continue;
		else {
			HanamiEntry *entry = [[HanamiEntry alloc] initWithIRI:entryIRI relativePath:[HanamiUtils relativePathFrom:_entriesPath to:entryIRI]];
			if (entry)
				[out addObject:entry];
		}
	return out;
}

- (OFString *)getTemplateAtIRI:(OFIRI *)iri defaultValue:(OFString *)defaultValue {
	if (![[OFFileManager defaultManager] fileExistsAtIRI:iri])
		return defaultValue;
	return [[OFString alloc] initWithContentsOfIRI:iri];
}

- (OFString *)getTemplate:(html_type_t)type {
	switch (type) {
		case HTML_HEAD:
			return [self getTemplateAtIRI:[_entriesPath IRIByAppendingPathComponent:@"head.html"] defaultValue:[HTMLHead copy]];
		case HTML_STORY:
			return [self getTemplateAtIRI:[_entriesPath IRIByAppendingPathComponent:@"story.html"] defaultValue:[HTMLStory copy]];
		case HTML_FOOT:
			return [self getTemplateAtIRI:[_entriesPath IRIByAppendingPathComponent:@"foot.html"] defaultValue:[HTMLFoot copy]];
	}
}

- (OFString *)getClientErrorStatusTemplate:(html_client_error_t)statusCode {
	return [self getTemplateAtIRI:[_entriesPath IRIByAppendingPathComponent:[OFString stringWithFormat:@"%d", 400 + statusCode]] defaultValue:[HTMLStatus copy]];
}

- (OFString *)getServerErrorStatusTemplate:(html_client_error_t)statusCode {
	return [self getTemplateAtIRI:[_entriesPath IRIByAppendingPathComponent:[OFString stringWithFormat:@"%d", 500 + statusCode]] defaultValue:[HTMLStatus copy]];
}


- (OFString *)getStatusTemplate:(html_error_type_t)statusType statusCode:(int)statusCode {
	switch (statusType) {
		case HTTP_CLIENT_ERROR_STATUS:
			return [self getClientErrorStatusTemplate:statusCode];
		case HTTP_SERVER_ERROR_STATUS:
			return [self getServerErrorStatusTemplate:statusCode];
	}
}

#pragma mark - Rendering

- (OFString *)renderEntryListAtIRI:(nonnull OFIRI *)iri varMap:(nonnull OFMutableDictionary *)varMap {
	OFMutableString *out = [[OFMutableString alloc] init];
	OFArray *entries = [self getEntriesAtIRI:iri];

	[out appendString:[HanamiUtils transformTemplate:[self getTemplate:HTML_HEAD] varMap:varMap]];
	if ([entries count] > 0) {
		// happy path
		for (HanamiEntry *entry in [entries sortedArray]) // sort here
			[out appendString:[entry render:[self getTemplate:HTML_STORY] varMap:varMap]];
	} else {
		// todo add 404
		[out appendString:[HanamiUtils transformTemplate:[self getTemplate:HTML_STORY] varMap:varMap]];
	}
	[out appendString:[HanamiUtils transformTemplate:[self getTemplate:HTML_FOOT] varMap:varMap]];
	return out;
}



- (void)writeClientErrorPage:(html_error_type_t)type statusCode:(int)statusCode response:(OFHTTPResponse *)response andVarMap:(OFMutableDictionary *)varMap {
	if (wrapStatusPages) {
		response.statusCode = statusCode;
		[self wrapResponse:response withBody:[HanamiUtils transformTemplate:[self getStatusTemplate:type statusCode:statusCode] varMap:varMap] andVarMap:varMap];
		return;
	}

	response.statusCode = statusCode;
	[response writeString:[HanamiUtils transformTemplate:[self getStatusTemplate:type statusCode:statusCode] varMap:varMap]];
}

@end
