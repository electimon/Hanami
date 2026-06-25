#import "Hanami.h"
#include <ObjFW/OFMutableDictionary.h>

#include <stdio.h>

#include <wregex.h>

OF_APPLICATION_DELEGATE(Hanami)

@implementation Hanami

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

static OFMutableDictionary *staticVarMap;

#pragma mark -

- (void)applicationDidFinishLaunching: (OFNotification *)notification
{
	// Configuration taken from ObjGemCap, would love to move it out of this method
	OFString *configPath;
	const OFOptionsParserOption options[] = {
		{ 'c', @"config", 1, NULL, &configPath },
		{ '\0', nil, 0, NULL, NULL },
	};
	OFOptionsParser *optionsParser =
	    [OFOptionsParser parserWithOptions: options];
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

	OFINIFile *config = [OFINIFile fileWithIRI:
	    [OFIRI fileIRIWithPath: configPath]];
	OFINISection *hanamiSection = [config sectionForName: @"hanami"];

	OFString *dataDir = [hanamiSection stringValueForKey:@"datadir"];

	if (dataDir == nil) {
		OFLog(@"Data Dir not specified in hanami.ini!");
		[OFApplication terminateWithStatus:1];
	}

	staticVarMap = [[OFMutableDictionary alloc] init];
	staticVarMap[@"$content_type"] = HTMLContentType;
	staticVarMap[@"$blog_title"] = [hanamiSection stringValueForKey:@"blog_title"];
	staticVarMap[@"$blog_description"] = [hanamiSection stringValueForKey:@"blog_description"];
	staticVarMap[@"$url"] = [hanamiSection stringValueForKey:@"url"];

	_server = [[OFHTTPServer alloc] init];
	_server.host = @"127.0.0.1";
	_server.port = 8999;
	_server.delegate = self;
	[_server start];
	OFLog(@"Hanami: Started HTTP server at: 127.0.0.1:8999");
}

#pragma mark - Utilities

// yes I STOLE it, STOLEEEEE IT, I KANGED ITTTTTT from blosxom
// note, i changed \\ to %5 in wrxcfg, thats why it looks funky
static const char *transformationRegex = "(%$%w+(?:::%w+)*(?:(?:->)?%{[-%w]+%})?)";

- (OFString *)transformTemplate:(OFString *)template varMap:(OFDictionary *)varMap {
	static bool initOk = false;
	static wregex_t *compiledTransformationRegex;
	if (!initOk) {
		int e = 0;
		compiledTransformationRegex = wrx_comp(transformationRegex, &e, NULL);
		if (!compiledTransformationRegex) {
			OFLog(@"Hanami: Failed to compile the transformation regex: %d, Bailing!", e);
			[OFApplication terminateWithStatus:1];
		} else {
			OFLog(@"RET WAS %d", e);
		}
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

			cursor = subm[0].end;
		}

		if (*cursor)
			[result appendUTF8String:cursor];

		[final appendFormat:@"%@\n", result];
	}
	return final;
}

#pragma mark -

#pragma mark - Delegate Methods

- (void)server:(nonnull OFHTTPServer *)server didReceiveRequest:(nonnull OFHTTPRequest *)request requestBody:(nullable OFStream *)requestBody response:(nonnull OFHTTPResponse *)response {
	OFMutableDictionary *varMap = [[OFMutableDictionary alloc] initWithDictionary:staticVarMap];
	varMap[@"$path"] = request.IRI.path;
	varMap[@"$url"] = varMap[@"$url"] ?: @"";

	response.statusCode = 200;
	response.headers = @{
		@"Content-Type": @"text/html; charset=$blog_encoding"
	};
	OFString *sending = [OFString stringWithFormat:@"%@%@%@", HTMLHead, HTMLStory, HTMLFoot];
	OFLog(@"%@", sending);
	[response writeString:[self transformTemplate:[OFString stringWithFormat:@"%@%@%@", HTMLHead, HTMLStory, HTMLFoot] varMap:varMap]];
}

#pragma mark -

@end
