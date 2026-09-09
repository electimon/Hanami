#import "HanamiConfig.h"

@implementation HanamiConfig

static OFMutableDictionary *instances;

+ (instancetype)instanceFor:(OFString *)name {
    if (!instances)
        instances = [[OFMutableDictionary alloc] init];
    HanamiConfig *configInstance = [instances objectForKey:name];
    if (!configInstance) {
        configInstance = [[HanamiConfig alloc] init];
        configInstance->configName = name;
        configInstance->iniFile = [OFINIFile fileWithIRI:[OFIRI fileIRIWithPath:[OFString stringWithFormat:@"configs/%@.ini", name]]];
        [instances setObject:configInstance forKey:name];
    }
    return configInstance;
}

- (OFString *)valueForKey:(OFString *)key defaultValue:(OFString *)defaultValue {
    OFINISection *section = [iniFile sectionForName:configName];
    return [section stringValueForKey:key defaultValue:defaultValue];
}

- (void)setValue:(OFString *)value forKey:(nonnull OFString *)key {
    OFINISection *section = [iniFile sectionForName:configName];
    [section setStringValue:value forKey:key];
    [iniFile writeToIRI:[OFIRI fileIRIWithPath:[OFString stringWithFormat:@"configs/%@.ini", configName]]];
}

@end
