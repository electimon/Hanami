#import "../../srcs/HanamiPlugin.h"
#import "../../srcs/HanamiConfig.h"
#import "../../srcs/HanamiUtils.h"

#define MAX_VISITORS 1000000

@interface HitCounterPlugin: OFObject <HanamiPlugin>
@end

Class HanamiPluginClass(void) {
    return [HitCounterPlugin class];
}

@implementation HitCounterPlugin {
    OFMutableSet *set;
}

- (instancetype)init {
    self = [super init];
    self->set = [[OFMutableSet alloc] init];
    OFIRI *ipsFileIRI = [[HanamiUtils getStateDirectory:[self name]] IRIByAppendingPathComponent:@"counter.ips"];
    if (![[OFFileManager defaultManager] fileExistsAtIRI:ipsFileIRI]) {
        OFFile *file = [self openIPsFile];
        [file close];
    }
    OFString *ips = [OFString stringWithContentsOfIRI:ipsFileIRI];
    for (OFString *str in [ips componentsSeparatedByCharactersInSet:[OFCharacterSet newlineCharacterSet]])
        if (str.length > 0 && set.count < MAX_VISITORS)
            [set addObject:str];
    return self;
}

- (OFFile *)openIPsFile {
    OFIRI *ipsFileIRI = [[HanamiUtils getStateDirectory:[self name]] IRIByAppendingPathComponent:@"counter.ips"];
    OFFile *ipsFile = [OFFile fileWithPath:[ipsFileIRI fileSystemRepresentation] mode:@"a"];
    ipsFile.buffersWrites = true;
    return ipsFile;
}

- (void)transformMap:(OFMutableDictionary *)varMap {
    OFString *requestIP = [[varMap valueForKey:@"$request::address"] stringBySHA1Hashing];
    OFString *requestPath = [varMap valueForKey:@"$request::path"];
    OFString *numStr;
    @synchronized (set) {
        if ([set containsObject:requestIP]) {
            numStr = [OFString stringWithFormat:@"%llu", [set count]];
            [self injectHitCounter:varMap counterVal:numStr];
            return;
        }
        if (set.count >= MAX_VISITORS) {
            [self injectHitCounter:varMap counterVal:[OFString stringWithFormat:@"%llu", set.count]];
            return;
        }
        [set addObject:requestIP];
        OFFile *ipsFile = [self openIPsFile];
@try {
        [ipsFile writeLine:requestIP];
        [ipsFile flushWriteBuffer];
} @finally {
        [ipsFile close];
}
        long long num = [set count];
        if ([requestPath isEqual:@"/"])
            num++;
        numStr = [OFString stringWithFormat:@"%lld", num];
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
