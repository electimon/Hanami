#import <ObjFW/ObjFW.h>

static const char * const month[] = {
    "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
};

@interface HanamiUtils : OFObject

+ (nullable OFString *)relativePathFrom:(nonnull OFIRI *)baseIRI to:(nonnull OFIRI *)fullIRI;
+ (OFString *)transformTemplate:(OFString *)template varMap:(OFDictionary *)varMap;
+ (nullable OFIRI *)resolve:(OFString *)userPath under:(OFIRI *)base;

@end