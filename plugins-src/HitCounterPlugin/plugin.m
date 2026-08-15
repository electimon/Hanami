#import "../../srcs/HanamiPlugin.h"
#include <ObjFW/OFMutableDictionary.h>
#import "../../srcs/HanamiConfig.h"

@interface HitCounterPlugin: OFObject <HanamiPlugin>
@end

Class HanamiPluginClass(void) {
    return [HitCounterPlugin class];
}

@implementation HitCounterPlugin {
    HanamiConfig *config;
    OFMutableSet *set;
}

- (instancetype)init {
    self = [super init];
    self->config = [HanamiConfig instanceFor:@"hitcounter"];
    self->set = [[OFMutableSet alloc] init];
    return self;
}

- (void)transformMap:(OFMutableDictionary *)varMap {
    OFString *requestIP = [[varMap valueForKey:@"$request::address"] stringBySHA1Hashing];
    OFString *requestPath = [varMap valueForKey:@"$request::path"];
    OFString *numStr;
    @synchronized (set) {
        if ([set containsObject:requestIP]) {
            numStr = [config valueForKey:@"counter" defaultValue:@"0"];
            [self injectHitCounter:varMap counterVal:numStr];
            return;
        }
        [set addObject:requestIP];
        long long num = [[config valueForKey:@"counter" defaultValue:@"0"] longLongValue];
        if ([requestPath isEqual:@"/"])
            num++;
        numStr = [OFString stringWithFormat:@"%lld", num];
        [config setValue:numStr forKey:@"counter"];
    }
    [self injectHitCounter:varMap counterVal:numStr];
}

- (void)injectHitCounter:(OFMutableDictionary *)varMap counterVal:(OFString *)counterVal {
    [varMap setObject:@" \
.hit-counter { \
  text-align: center; \
  margin-top: 20px; \
  font-size: 11px; \
  color: #7a4e4e; \
} \
.counter-digits { margin-top: 4px; } \
.counter-digit { \
  background: #3a1818; \
  color: #e89090; \
  font-family: \"Courier New\", monospace; \
  font-size: 14px; \
  font-weight: bold; \
  padding: 4px 5px; \
  border: 1px inset #683838; \
  margin-right: 1px; \
} \
" forKey:@"$hitcounter::css"];
    OFMutableString *counterDigitString = [[OFMutableString alloc] init];
    for (int counter = 0; counter < [counterVal length]; counter++)
        [counterDigitString appendString:[OFString stringWithFormat:@"<span class=\"counter-digit\">%c</span>", [counterVal characterAtIndex:counter]]];
// <span class=\"counter-digit\">1</span><span class=\"counter-digit\">2</span><span class=\"counter-digit\">6</span><span class="counter-digit">7</span>
    [varMap setObject:[OFString stringWithFormat:@" \
      <div class=\"hit-counter\"> \
        visitors:          <div class=\"counter-digits\"> \
                %@ \
          </div> \
      </div> \
", counterDigitString] forKey:@"$hitcounter::html"];
}

- (OFString *)name {
    return @"HitCounterPlugin";
}

- (OFString *)author {
    return @"Renn";
}

- (OFString *)version {
    return @"1.0";
}

@end