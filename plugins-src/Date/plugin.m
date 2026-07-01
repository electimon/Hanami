#import "../../srcs/HanamiPlugin.h"

@interface DatePlugin: OFObject <HanamiPlugin>
@end

Class HanamiPluginClass(void) {
    return [DatePlugin class];
}

@implementation DatePlugin

const char * const weekday[] = {
  "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday",
};    

const char * const month[]   = {
  "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December",
};

- (void)transformMap:(OFMutableDictionary *)varMap {
    OFDate *date = [OFDate date];
    [varMap setValue:[OFString stringWithFormat:@"%s", weekday[date.localDayOfWeek]] forKey:@"$date::day"];
    [varMap setValue:[OFString stringWithFormat:@"%s", month[date.localMonthOfYear - 1]] forKey:@"$date::month"];
    [varMap setValue:[OFString stringWithFormat:@"%d", date.localYear] forKey:@"$date::year"];
}

- (OFString *)name {
    return @"DatePlugin";
}

- (OFString *)author {
    return @"Renn";
}

- (OFString *)version {
    return @"1.0";
}

@end