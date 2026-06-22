#import "Hanami.h"

#include <stdio.h>

#include <regex.h>

OF_APPLICATION_DELEGATE(Hanami)

@implementation Hanami

#pragma mark - Constants

static const OFString *HTMLHead = @"'<!DOCTYPE html PUBLIC \"-//W3C//DTD HTML 4.01 Transitional//EN\" \"http://www.w3.org/TR/html4/loose.dtd\">"
"<html>"
"    <head>"
"        <meta http-equiv=\"content-type\" content=\"$content_type\" >"
"        <link rel=\"alternate\" type=\"application/rss+xml\" title=\"RSS\" href=\"$url/index.rss\" >"
"        <title>$blog_title $path_info_da $path_info_mo $path_info_yr</title>"
"    </head>"
"    <body>"
"        <div align=\"center\">"
"            <h1>$blog_title</h1>"
"            <p>$path_info_da $path_info_mo $path_info_yr</p>"
"        </div>";

static const OFString *HTMLStory = @"<div>"
"    <h3><a name=\"$fn\">$title</a></h3>"
"    <div>$body</div>"
"    <p>posted at: $ti | path: <a href=\"$url$path\">$path</a> | <a href=\"$url/$yr/$mo_num/$da#$fn\">permanent link to this entry</a></p>"
"</div>";

static const OFString *HTMLFoot = @"<div align=\"center\">"
"            <a href=\"http://blosxom.sourceforge.net/\"><img src=\"http://blosxom.sourceforge.net/images/pb_blosxom.gif\" alt=\"powered by blosxom\" border=\"0\" width=\"90\" height=\"33\" ></a>"
"        </div>"
"    </body>"
"</html>";

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

	_server = [[OFHTTPServer alloc] init];
	_server.host = @"127.0.0.1";
	_server.port = 8999;
	_server.delegate = self;
	[_server start];
	OFLog(@"Hanami: Started HTTP server at: 127.0.0.1:8999");
}

#pragma mark - Utilities

// yes I STOLE it, STOLEEEEE IT, I KANGED ITTTTTT from blosxom 
static const char *transformationRegex = "(\\$\\w+(?:::\\w+)*(?:(?:->)?\\{[-\\w]+\\})?)";

- (OFString *)transformTemplate:(OFString *)template varMap:(OFDictionary *)varMap {
	static bool initOk = false;
	static regex_t *compiledTransformationRegex;
	if (!initOk) {
		int e = 0;
		compiledTransformationRegex = regcomp(compiledTransformationRegex, transformationRegex, NULL);
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

	int ret = wrx_exec(compiledTransformationRegex, [template UTF8String], subm, compiledTransformationRegex->n_subm);
	if (ret == 1)
		for (int i = 0; i < compiledTransformationRegex->n_subm; i++) {
			/* Get the length of the submatch */
			int len = subm[i].end - subm[i].beg;

			/* Allocate memory for it */
			char *sm = malloc(len + 1);
			if(!sm) {
				fprintf(stderr, "Error: out of memory");
				exit(EXIT_FAILURE);
			}

			/* Copy it */
			strncpy(sm, subm[i].beg, len);
			sm[len] = 0;

			/* and print */
			OFLog(@"%s ", sm);
			free(sm);
		}
	else
		OFLog(@"ret is: %d", ret);
	return template;
}

#pragma mark -

#pragma mark - Delegate Methods

- (void)server:(nonnull OFHTTPServer *)server didReceiveRequest:(nonnull OFHTTPRequest *)request requestBody:(nullable OFStream *)requestBody response:(nonnull OFHTTPResponse *)response {
	response.statusCode = 200;
	response.headers = @{
		@"Content-Type": @"text/html; charset=$blog_encoding"
	};
	OFString *sending = [OFString stringWithFormat:@"%@%@%@", HTMLHead, HTMLStory, HTMLFoot];
	OFLog(@"%@", sending);
	[response writeString:[self transformTemplate:[OFString stringWithFormat:@"%@%@%@", HTMLHead, HTMLStory, HTMLFoot] varMap:nil]];
}

#pragma mark -

@end
