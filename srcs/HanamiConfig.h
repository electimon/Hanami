#import <ObjFW/ObjFW.h>

@interface HanamiConfig : OFObject {
    OFString *configName;
    OFINIFile *iniFile;
}
+ (instancetype)instanceFor:(OFString *)name;
- (OFString *)valueForKey:(OFString *)key defaultValue:(OFString *)defaultValue;
- (void)setValue:(OFString *)value forKey:(nonnull OFString *)key;
@end
