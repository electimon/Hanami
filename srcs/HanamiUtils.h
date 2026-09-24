#import <ObjFW/ObjFW.h>
#import "HanamiTemplateHandler.h"

static const char * const month[] = {
    "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
};

@interface HanamiUtils : OFObject

+ (nullable OFString *)relativePathFrom:(nonnull OFIRI *)baseIRI to:(nonnull OFIRI *)fullIRI;
+ (OFString *)transformTemplate:(OFString *)template varMap:(OFDictionary *)varMap;
+ (nullable OFIRI *)resolve:(OFString *)userPath under:(OFIRI *)base;
+ (OFString *)getTemplateAtIRI:(OFIRI *)iri defaultValue:(OFString *)defaultValue;
+ (OFString *)getTemplate:(html_type_t)type;
+ (void)wrapResponse:(OFHTTPResponse *)response withBody:(OFString *)story andVarMap:(OFMutableDictionary *)varMap;
@end