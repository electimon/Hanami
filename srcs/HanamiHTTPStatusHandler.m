#import "HanamiHTTPStatusHandler.h"
#import "HanamiConfig.h"
#import "HanamiDynamicConfig.h"
#import "HanamiUtils.h"

@implementation HanamiHTTPStatusHandler

+ (OFString *)getStatusTemplate:(int)statusCode {
    return [HanamiUtils getTemplateAtIRI:[entriesPath IRIByAppendingPathComponent:[OFString stringWithFormat:@"%d.%@", statusCode, defaultFileExtension]] defaultValue:[HTMLStatus copy]];
}

+ (void)handleStatus:(int)statusCode forRequest:(HanamiRequestContext *)reqCtx {
    [reqCtx setObject:[OFString stringWithFormat:@"%d", statusCode] forKey:@"$status_code"];
    if ([reqCtx objectForKey:@"$int_error"])
        [reqCtx setObject:[reqCtx objectForKey:@"$int_error"] forKey:@"$error"];
    else
        [reqCtx setObject:OFHTTPStatusCodeString(statusCode) forKey:@"$error"];
    [reqCtx setStatusCode:statusCode];
@try {
	if ([[[HanamiConfig instanceFor:@"hanami"] valueForKey:@"wrap_status_pages" defaultValue:@"1"] intValue])
		[HanamiUtils wrapContext:reqCtx withBody:[HanamiUtils transformTemplate:[self getStatusTemplate:statusCode] varMap:reqCtx.varMap]];
	else
    	[reqCtx.response writeString:[HanamiUtils transformTemplate:[self getStatusTemplate:statusCode] varMap:reqCtx.varMap]];
} @catch (OFWriteFailedException *ex) {
    OFLog(@"Hanami: Lost TCP response pipe");
}
}
@end