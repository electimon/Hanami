#import "HanamiTemplateHandler.h"
#import "HanamiEntry.h"
#import "HanamiConfig.h"
#import "HanamiUtils.h"

@implementation HanamiTemplateHandler

+ (OFString *)renderEntryListAtIRI:(nonnull OFIRI *)iri varMap:(nonnull OFMutableDictionary *)varMap {
	OFMutableString *out = [[OFMutableString alloc] init];
	OFArray *entries = [HanamiEntry getEntriesAtIRI:iri];

	[out appendString:[HanamiUtils transformTemplate:[HanamiUtils getTemplate:HTML_HEAD] varMap:varMap]];
	if ([entries count] > 0) {
		// happy path
		for (HanamiEntry *entry in [entries sortedArray]) // sort here
			[out appendString:[entry render:[HanamiUtils getTemplate:HTML_STORY] varMap:varMap]];
	} else {
		// todo add 404
		[out appendString:[HanamiUtils transformTemplate:[HanamiUtils getTemplate:HTML_STORY] varMap:varMap]];
	}
	[out appendString:[HanamiUtils transformTemplate:[HanamiUtils getTemplate:HTML_FOOT] varMap:varMap]];
	return out;
}

@end