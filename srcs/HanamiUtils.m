#import "HanamiUtils.h"

#include "../wregex/wregex.h"

@implementation HanamiUtils

+ (nullable OFString *)relativePathFrom:(nonnull OFIRI *)baseIRI to:(nonnull OFIRI *)fullIRI {
	OFString *basePath = baseIRI.path;
	OFString *fullPath = fullIRI.path;

	if (![fullPath hasPrefix:basePath])
		return nil;

	OFString *rel = [fullPath substringFromIndex:basePath.length];
	if (![rel hasPrefix:@"/"])
		rel = [OFString stringWithFormat:@"/%@", rel];
	return rel;
}

// yes I STOLE it, STOLEEEEE IT, I KANGED ITTTTTT from blosxom
// note, i changed \\ to %5 in wrxcfg, thats why it looks funky
static const char *transformationRegex = "(%$%w+(:::%w+)*(:(:->)?%{[-%w]+%})?)";

+ (OFString *)transformTemplate:(OFString *)template varMap:(OFDictionary *)varMap {
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

// writen by ai
+ (nullable OFIRI *)resolve:(OFString *)userPath under:(OFIRI *)base {
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

@end