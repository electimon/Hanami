#import "Hanami.h"
#include <ObjFW/OFException.h>
#include <asm-generic/errno-base.h>
#include <ObjFW/OFCreateDirectoryFailedException.h>
#include <ObjFW/OFFileManager.h>
#include <ObjFW/OFObject.h>
#include <ObjFW/OFArray.h>
#include "HanamiPluginResult.h"
#import "HanamiUtils.h"
#import "HanamiEntry.h"
#import "HanamiPlugin.h"
#import "HanamiConfig.h"

#include <stdio.h>

OF_APPLICATION_DELEGATE(Hanami)

@interface Hanami (Private)
@property (nonatomic, strong) OFIRI *_entriesPath;
@property (nonatomic, strong) OFIRI *_staticPath;
@property (nonatomic, strong) OFIRI *_pluginsPath;
@property (nonatomic, strong) OFArray *_excluded;
@end

@implementation Hanami

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

typedef enum {
	HTML_HEAD = 0,
	HTML_STORY,
	HTML_FOOT
} html_type_t;

static OFMutableDictionary *staticVarMap;

#pragma mark -

- (void)applicationDidFinishLaunching: (OFNotification *)notification
{
	// Configuration taken from ObjGemCap, would love to move it out of this method
	OFString *__autoreleasing configPath = nil;
	const OFOptionsParserOption options[] = {
		{ 'c', @"config", 1, NULL, &configPath },
		{ '\0', nil, 0, NULL, NULL },
	};
	OFOptionsParser *optionsParser = [OFOptionsParser parserWithOptions: options];
	OFUnichar option;

	while ((option = [optionsParser nextOption]) != '\0') {
		switch (option) {
		case ':':
			if (optionsParser.lastLongOption != nil)
				[OFStdErr writeFormat:
				    @"%@: Argument for option --%@ missing\n",
				    [OFApplication programName],
				    optionsParser.lastLongOption];
			else
				[OFStdErr writeFormat:
				    @"%@: Argument for option -%C missing\n",
				    [OFApplication programName],
				    optionsParser.lastOption];

			[OFApplication terminateWithStatus: 1];
			break;
		case '=':
			[OFStdErr writeFormat:
			    @"%@: Option --%@ takes no argument\n",
			    [OFApplication programName],
			    optionsParser.lastLongOption];

			[OFApplication terminateWithStatus: 1];
			break;
		case '?':
			if (optionsParser.lastLongOption != nil)
				[OFStdErr writeFormat:
				    @"%@: Unknown option: --%@\n",
				    [OFApplication programName],
				    optionsParser.lastLongOption];
			else
				[OFStdErr writeFormat:
				    @"%@: Unknown option: -%@\n",
				    [OFApplication programName],
				    optionsParser.lastOption];

			[OFApplication terminateWithStatus: 1];
			break;
		}
	}

	HanamiConfig *config = [HanamiConfig instanceFor:@"hanami"];

	// Plugins
	_pluginsPath = [OFIRI fileIRIWithPath:[config valueForKey:@"plugin_dir" defaultValue:@"plugins"] isDirectory:1];
	_plugins = [[OFMutableArray alloc] init];
	_pluginModules = [[OFMutableArray alloc] init];

	// create state dir
	OFIRI *statePath = [OFIRI fileIRIWithPath:[config valueForKey:@"state_dir" defaultValue:@"state"] isDirectory:1];
	@try {
		[[OFFileManager defaultManager] createDirectoryAtIRI:statePath];
	} @catch (OFCreateDirectoryFailedException *ex) {
		if (ex.errNo == EEXIST)
			OFLog(@"Hanami: State directory already exists ^_^");
		else
			@throw (ex); // rethrow just in case
	}

	[self loadPlugins];

	// Entries
	_entriesPath = [OFIRI fileIRIWithPath:[config valueForKey:@"entries_dir" defaultValue:@"entries"] isDirectory:1];

	// static files
	_staticPath = [OFIRI fileIRIWithPath:[config valueForKey:@"static_dir" defaultValue:@"static"] isDirectory:1];

	// exclusions
	OFString *exclusions = [config valueForKey:@"exclude" defaultValue:@""];
	if (exclusions != nil)
		_excluded = [exclusions componentsSeparatedByString:@" "];
	else
		_excluded = [[OFArray alloc] init];

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

- (void)wrapResponse:(OFHTTPResponse *)response withStory:(id)story \
	andVarMap:(OFMutableDictionary *)varMap {
	[response writeString:[HanamiUtils transformTemplate:[self getTemplate:HTML_HEAD] varMap:varMap]];
	if ([story isKindOfClass:[OFString class]])
		[response writeString:story];
	else
		[story render:[self getTemplate:HTML_STORY] varMap:varMap];
	[response writeString:[HanamiUtils transformTemplate:[self getTemplate:HTML_FOOT] varMap:varMap]];
}

- (void)server:(nonnull OFHTTPServer *)server didReceiveRequest:(nonnull OFHTTPRequest *)request requestBody:(nullable OFStream *)requestBody response:(nonnull OFHTTPResponse *)response {
	OFArray *pathComponents = request.IRI.pathComponents;
	for (OFString *comp in pathComponents)
		if ([comp isEqual:@".."] || [comp containsString:@"\\"])
			return; // should be bail

	if ([pathComponents count] > 1 && [[pathComponents objectAtIndex:1] isEqual:@"static"]) {
		OFString *rel = [[pathComponents objectsInRange:OFMakeRange(2, pathComponents.count - 2)] componentsJoinedByString:@"/"];
		OFIRI *iri = [HanamiUtils resolve:rel under:_staticPath];
		if (iri == nil) return; // todo add 404 // should be bail
		if ([[OFFileManager defaultManager] fileExistsAtIRI:iri])
			[response writeData:[OFData dataWithContentsOfIRI:iri]];
		else
			return; // should be bail
		return;
	}

	OFData *requestData;
	if (requestBody != nil)
		requestData = [requestBody readDataUntilEndOfStream];

	OFMutableDictionary *varMap = [[OFMutableDictionary alloc] initWithDictionary:staticVarMap];
	// fill in some info that could be useful for widgets like request ip
	[varMap setValue:OFSocketAddressString(request.remoteAddress) forKey:@"$request::address"];
	[varMap setValue:request.IRI.path forKey:@"$request::path"];

	OFLog(@"Hanami: Registered Plugins: %@", _plugins);

	for (id<HanamiPlugin> plugin in _plugins) {
		OFLog(@"Hanami: Calling %@ to transform map", plugin);
		[plugin transformMap:varMap];
	}

	for (id<HanamiPlugin> plugin in _plugins) {
		if (![plugin respondsToSelector:@selector(handleRequest:requestData:andVarMap:)])
			continue; // meep, our plugin doesnt respond to this
		OFLog(@"Hanami: Calling %@ to handle request", plugin);
		HanamiPluginResult *plugResult = [plugin handleRequest:request requestData:requestData andVarMap:varMap];
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
				[self wrapResponse:response withStory:[plugResult render:[self getTemplate:HTML_STORY] varMap:varMap] andVarMap:varMap];
			return;
}
@catch (OFException *ex) {
			OFLog(@"Encountered Exception!, plugin: %@, exception: %@", plugin, ex);
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
			[self wrapResponse:response withStory:[entry render:[self getTemplate:HTML_STORY] varMap:varMap] andVarMap:varMap];
		else
			bail; // todo add 404
	}
}

#pragma mark -

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

#pragma mark -

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

- (OFString *)getTemplate:(html_type_t)type {
	OFString *out;
	switch (type) {
		case HTML_HEAD: {
			OFIRI *iri = [_entriesPath IRIByAppendingPathComponent:@"head.html"];
			if (![[OFFileManager defaultManager] fileExistsAtIRI:iri])
				out = [HTMLHead copy];
			else
				out = [[OFString alloc] initWithContentsOfIRI:[_entriesPath IRIByAppendingPathComponent:@"head.html"]];
			break;
		}
		case HTML_STORY: {
			OFIRI *iri = [_entriesPath IRIByAppendingPathComponent:@"story.html"];
			if (![[OFFileManager defaultManager] fileExistsAtIRI:iri])
				out = [HTMLStory copy];
			else
				out = [[OFString alloc] initWithContentsOfIRI:[_entriesPath IRIByAppendingPathComponent:@"story.html"]];
			break;
		}
		case HTML_FOOT: {
			OFIRI *iri = [_entriesPath IRIByAppendingPathComponent:@"foot.html"];
			if (![[OFFileManager defaultManager] fileExistsAtIRI:iri])
				out = [HTMLFoot copy];
			else
				out = [[OFString alloc] initWithContentsOfIRI:[_entriesPath IRIByAppendingPathComponent:@"foot.html"]];
			break;
		}
	}
	return out;
}
@end
