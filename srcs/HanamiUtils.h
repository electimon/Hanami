#import <ObjFW/ObjFW.h>
#import "HanamiTemplateHandler.h"
#import "HanamiClasses.h"

#ifdef OF_WINDOWS
    const static OFString *PATH_SEP = @"\\";
#else
    const static OFString *PATH_SEP = @"/";
#endif

static const char * const month[] = {
    "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
};

@interface HanamiUtils : OFObject

+ (nullable OFString *)relativePathFrom:(nonnull OFIRI *)baseIRI to:(nonnull OFIRI *)fullIRI;
+ (OFString *)transformTemplate:(OFString *)template varMap:(OFDictionary *)varMap;
+ (nullable OFIRI *)resolve:(OFString *)userPath under:(OFIRI *)base;
+ (OFString *)getTemplateAtIRI:(OFIRI *)iri defaultValue:(OFString *)defaultValue;
+ (OFString *)getTemplate:(html_type_t)type;
+ (void)wrapContext:(HanamiRequestContext *)reqCtx withBody:(OFString *)story;
+ (int)writeObject:(id)object toResponse:(HanamiRequestContext *)reqCtx;
+ (OFString *)getSupportTemplate:(OFString *)name for:(OFString *)class;
+ (OFIRI *)getStateDirectory:(OFString *)forClass;
@end