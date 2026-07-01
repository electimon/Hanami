#import "Hanami.h"
#import "HanamiPlugin.h"

#include <stdio.h>

#include "../wregex/wregex.h"

OF_APPLICATION_DELEGATE(Hanami)

@implementation Hanami {
	OFIRI *_entriesPath;
	OFIRI *_staticPath;
	OFIRI *_pluginsPath;
}

#pragma mark - Constants

static const OFString *HTMLContentType = @"text/html; charset=UTF-8";

static const OFString *HTMLHead = @"<!DOCTYPE html PUBLIC \"-//W3C//DTD HTML 4.01 Transitional//EN\" \"http://www.w3.org/TR/html4/loose.dtd\">\n"
"<html>\n"
"    <head>\n"
"        <meta http-equiv=\"content-type\" content=\"$content_type\" >\n"
"        <link rel=\"alternate\" type=\"application/rss+xml\" title=\"RSS\" href=\"$url/index.rss\" >\n"
"        <title>$blog_title $path_info_da $path_info_mo $path_info_yr$path_info_yr</title>\n"
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

	if (configPath == nil)
		configPath = @"hanami.ini";

	OFINIFile *config = [OFINIFile fileWithIRI:[OFIRI fileIRIWithPath: configPath]];
	OFINISection *hanamiSection = [config sectionForName: @"hanami"];

	// Plugins
	OFString *_pluginsPathStr = [hanamiSection stringValueForKey:@"plugin_dir"];
	if (_pluginsPathStr == nil)
		_pluginsPathStr = @"plugins";
	_pluginsPath = [OFIRI fileIRIWithPath:_pluginsPathStr isDirectory:1];

	_plugins = [[OFMutableArray alloc] init];
	_pluginModules = [[OFMutableArray alloc] init];

	[self loadPlugins];

	// Entries
	OFString *_entriesPathStr = [hanamiSection stringValueForKey:@"entries_dir"];
	if (_entriesPathStr == nil)
		_entriesPathStr = @"entries";
	_entriesPath = [OFIRI fileIRIWithPath:_entriesPathStr isDirectory:1];

	// static files
	OFString *_staticPathStr = [hanamiSection stringValueForKey:@"static_dir"];
	if (_staticPathStr == nil)
		_staticPathStr = @"static";
	_staticPath = [OFIRI fileIRIWithPath:_staticPathStr isDirectory:1];

	// static var map, global constants
	staticVarMap = [[OFMutableDictionary alloc] init];
	staticVarMap[@"$content_type"] = HTMLContentType;
	staticVarMap[@"$blog_title"] = [hanamiSection stringValueForKey:@"blog_title"];
	staticVarMap[@"$blog_description"] = [hanamiSection stringValueForKey:@"blog_description"];
	staticVarMap[@"$url"] = [hanamiSection stringValueForKey:@"url"];

	// host n port
	OFString *_host = [hanamiSection stringValueForKey:@"host"];
	int _port = [[hanamiSection stringValueForKey:@"port"] intValue];

	_server = [[OFHTTPServer alloc] init];
	_server.host = _host;
	_server.port = _port;
	_server.delegate = self;
	[_server start];
	OFLog(@"Hanami: Started HTTP server at: %@:%d, version: %@", _host, _port, VERSION);
}

#pragma mark - Utilities

// yes I STOLE it, STOLEEEEE IT, I KANGED ITTTTTT from blosxom
// note, i changed \\ to %5 in wrxcfg, thats why it looks funky
static const char *transformationRegex = "(%$%w+(:::%w+)*(:(:->)?%{[-%w]+%})?)";

- (OFString *)transformTemplate:(OFString *)template varMap:(OFDictionary *)varMap {
	static bool initOk = false;
	static wregex_t *compiledTransformationRegex;
	if (!initOk) {
		int e = 0;
		compiledTransformationRegex = wrx_comp(transformationRegex, &e, NULL);
		if (!compiledTransformationRegex) {
			OFLog(@"Hanami: Failed to compile the transformation regex: %d, Bailing!", e);
			[OFApplication terminateWithStatus:1];
		}
		initOk = true;
	}

	wregmatch_t *subm = calloc(sizeof *subm, compiledTransformationRegex->n_subm);
	if (!subm) {
		OFLog(@"Hanami: Could not allocate the array of submatches, Bailing!");
		wrx_free(compiledTransformationRegex);
		[OFApplication terminateWithStatus:1];
	}

	OFArray *chunks = [[template componentsSeparatedByString:@"\n"] mutableCopy];
	OFMutableString *final = [[OFMutableString alloc] init];

	for (OFString *chunk in chunks) {
		const char *base = [chunk UTF8String];
		const char *cursor = base;
		OFMutableString *result = [OFMutableString string];

		while (wrx_exec(compiledTransformationRegex, cursor, subm, compiledTransformationRegex->n_subm) == 1) {
			if (subm[0].beg > cursor)
				[result appendUTF8String:cursor length:(subm[0].beg - cursor)];

			int len = subm[0].end - subm[0].beg;
			OFString *match = [OFString stringWithUTF8String:subm[0].beg length:len];
			OFString *replacement = [varMap valueForKey:match];
			[result appendString:(replacement ?: @"")];

			if (subm[0].end == subm[0].beg) {
				if (*subm[0].end == '\0') break;
				[result appendUTF8String:subm[0].end length:1];
				cursor = subm[0].end + 1;
			} else {
				cursor = subm[0].end;
			}
		}

		if (*cursor)
			[result appendUTF8String:cursor];

		[final appendFormat:@"%@\n", result];
	}
	free(subm);
	return final;
}

#pragma mark -

#pragma mark - Delegate Methods

// writen by ai
- (nullable OFIRI *)resolve:(OFString *)userPath under:(OFIRI *)base {
	OFIRI *target = [[base IRIByAppendingPathComponent:userPath] IRIByStandardizingPath];   // collapses . and .. lexically

	OFString *basePfx = base.path;
	if (![basePfx hasSuffix:@"/"])
		basePfx = [basePfx stringByAppendingString:@"/"];

	OFString *tgt = target.path;
#ifdef OF_WINDOWS
	// NTFS is case-insensitive: win.ini == WIN.INI == Win.Ini
	if (![tgt.lowercaseString hasPrefix:basePfx.lowercaseString])
		return nil;
#else
	if (![tgt hasPrefix:basePfx])
		return nil;
#endif
	return target;
}

// u may be asking, why? well i tried goto and it fucking killed my app, random crashes, thanks clang
#define bail {\
@try { \
	[response writeString:[self transformTemplate:[OFString stringWithFormat:@"%@%@%@", [self getTemplate:HTML_HEAD], [self getTemplate:HTML_STORY], [self getTemplate:HTML_FOOT]] varMap:varMap]]; \
} @catch (OFException *ex) { OFLog(@"%@", ex);} \
return; }

- (void)server:(nonnull OFHTTPServer *)server didReceiveRequest:(nonnull OFHTTPRequest *)request requestBody:(nullable OFStream *)requestBody response:(nonnull OFHTTPResponse *)response {
	OFMutableDictionary *varMap = [[OFMutableDictionary alloc] initWithDictionary:staticVarMap];
	varMap[@"$url"] = varMap[@"$url"] ?: @"/";

	for (id<HanamiPlugin> plugin in _plugins)
		[plugin transformMap:varMap];

	response.statusCode = 200;
	response.headers = @{
		@"Content-Type": (OFString *)HTMLContentType
	};
	OFArray *pathComponents = request.IRI.pathComponents;
	for (OFString *comp in pathComponents)
		if ([comp isEqual:@".."] || [comp containsString:@"\\"])
			bail;
	if ([request.IRI.path isEqual:@"/"]) {
		[response writeString:[self renderEntryListAtIRI:_entriesPath varMap:varMap]];
		return;
	} else if ([pathComponents count] > 1 && [[pathComponents objectAtIndex:1] isEqual:@"static"]) {
		OFString *rel = [[pathComponents objectsInRange:OFMakeRange(2, pathComponents.count - 2)] componentsJoinedByString:@"/"];
		OFIRI *iri = [self resolve:rel under:_staticPath];
		if (iri == nil) bail;
		if ([[OFFileManager defaultManager] fileExistsAtIRI:iri])
			[response writeData:[OFData dataWithContentsOfIRI:iri]];
		else
			bail;
		return;
	} else if ([[request.IRI.path pathExtension] length] < 1) {
		OFIRI *iri = [self resolve:request.IRI.path under:_entriesPath];
		if (iri == nil) bail;
		if (![[OFFileManager defaultManager] directoryExistsAtIRI:iri]) {
			OFLog(@"IRI does not exist: %@", iri);
			bail;
		}
		[response writeString:[self renderEntryListAtIRI:iri varMap:varMap]];
		return;
	}
	// } else {
	// 	OFIRI *iri = [self resolve:request.IRI.path under:_entriesPath];
	// 	if (iri == nil) bail;
	// 	[self addEntry:iri varMap:varMap];

	// }
}

#pragma mark -

#pragma mark - Plugins

- (void)loadPlugins {
	// the idea is init.d style, 01, 02, 03 is the order
	for (OFIRI *file in [[OFFileManager defaultManager] contentsOfDirectoryAtIRI:_pluginsPath]) {
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
const char * const month[]   = {
  "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
};

- (nullable OFString *)relativePathFrom:(nonnull OFIRI *)baseIRI to:(nonnull OFIRI *)fullIRI {
	OFString *basePath = baseIRI.path;
	OFString *fullPath = fullIRI.path;

	if (![fullPath hasPrefix:basePath])
		return nil;

	OFString *rel = [fullPath substringFromIndex:basePath.length];
	if (![rel hasPrefix:@"/"])
		rel = [OFString stringWithFormat:@"/%@", rel];
	return rel;
}

- (OFString *)renderEntryListAtIRI:(nonnull OFIRI *)iri varMap:(nonnull OFMutableDictionary *)varMap {
	OFMutableString *out = [[OFMutableString alloc] init];
	[out appendString:[self transformTemplate:[self getTemplate:HTML_HEAD] varMap:varMap]];
	[self appendEntriesAtIRI:iri intoString:out varMap:varMap];
	[out appendString:[self transformTemplate:[self getTemplate:HTML_FOOT] varMap:varMap]];
	return out;
}

- (void)appendEntriesAtIRI:(nonnull OFIRI *)iri intoString:(nonnull OFMutableString *)out varMap:(nonnull OFMutableDictionary *)varMap {
	OFArray *contents = [[OFFileManager defaultManager] contentsOfDirectoryAtIRI:iri];
	for (OFIRI *entryIRI in contents) {
		if ([entryIRI isEqual:[_entriesPath IRIByAppendingPathComponent:@"story.html"]] || [entryIRI isEqual:[_entriesPath IRIByAppendingPathComponent:@"head.html"]] || [entryIRI isEqual:[_entriesPath IRIByAppendingPathComponent:@"foot.html"]])
			continue;
		if ([[OFFileManager defaultManager] directoryExistsAtIRI:entryIRI]) {
			[self appendEntriesAtIRI:entryIRI intoString:out varMap:varMap];
			continue;
		}
		[self addEntry:entryIRI varMap:varMap];
		[out appendString:[self transformTemplate:[self getTemplate:HTML_STORY] varMap:varMap]];
	}
}

- (void)addEntry:(OFIRI *)entry varMap:(OFMutableDictionary *)varMap {
	if (![[OFFileManager defaultManager] fileExistsAtIRI:entry]) {
		OFLog(@"Requested Entry does not exist: %@", entry);
		return;
	}
	OFString *contents;
	@try {
		contents = [[OFString alloc] initWithContentsOfIRI:entry];
	} @catch (OFException *ex) {
		OFLog(@"Got Exception: %@", ex);
		return;
	}
	OFFileAttributes attributes = [[OFFileManager defaultManager] attributesOfItemAtIRI:entry];
	OFDate *modDate = [attributes valueForKey:OFFileModificationDate];
	if (modDate) {
		[varMap setValue:[OFString stringWithFormat:@"%s", month[modDate.localMonthOfYear - 1]] forKey:@"$mo"];
		[varMap setValue:[OFString stringWithFormat:@"%d", modDate.localDayOfMonth] forKey:@"$da"];
		[varMap setValue:[OFString stringWithFormat:@"%d", modDate.localYear] forKey:@"$yr"];
	}

	size_t idx = [contents indexOfCharacterFromSet:[OFCharacterSet newlineCharacterSet]];

	OFString *first, *rest;
	if (idx != OFNotFound) {
		first = [contents substringWithRange: OFMakeRange(0, idx)];
		rest = [contents substringWithRange:OFMakeRange(idx + 1, contents.length - idx - 1)];
	} else {
		first = contents;
		rest = @"";
	}
	[varMap setValue:first forKey:@"$title"];
	[varMap setValue:rest forKey:@"$body"];
	[varMap setValue:[entry.lastPathComponent stringByDeletingPathExtension] forKey:@"$fn"];
	[varMap setValue:[[self relativePathFrom:_entriesPath to:entry] stringByDeletingLastPathComponent] forKey:@"$path"];
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