#import <ObjFW/ObjFW.h>
#import "HanamiTemplateDefaults.h"

typedef enum {
	HTML_HEAD = 0,
	HTML_STORY,
	HTML_FOOT
} html_type_t;

@interface HanamiTemplateHandler : OFObject
+ (OFString *)renderEntryListAtIRI:(nonnull OFIRI *)iri varMap:(nonnull OFMutableDictionary *)varMap;
@end