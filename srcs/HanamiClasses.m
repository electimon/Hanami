#import "HanamiClasses.h"
#import "HanamiHTTPStatusHandler.h"

@implementation HanamiRequestContext {
    BOOL isStaticFileRequest;
    OFData *requestData;
}

- (void)setDefaults {
	// fill in some info that could be useful for widgets like request ip
	[_varMap setValue:OFSocketAddressString(_request.remoteAddress) forKey:@"$request::address"];
	[_varMap setValue:_request.IRI.path forKey:@"$request::path"];
    // we default to success because we're happy people around these parts
	[self setStatusCode:200];
    _response.headers = [[OFMutableDictionary alloc] init];
	[self setContentType:[_varMap valueForKey:@"$content_type"]];
}

+ (HanamiRequestContext * _Nonnull)contextFrom:(OFHTTPRequest * _Nonnull)request withRequestBody:(OFStream * _Nullable)requestBody response:(OFHTTPResponse * _Nonnull)response andVarMap:(OFMutableDictionary * _Nonnull)varMap {
    HanamiRequestContext *klazz = [[HanamiRequestContext alloc] init];
    klazz->_request = request;
    klazz->_requestBody = requestBody;
    klazz->_response = response;
    klazz->_varMap = varMap;
    [klazz setDefaults];
    return klazz;
}

- (BOOL)isStaticFileRequestGetter {
    if (isStaticFileRequest)
        return isStaticFileRequest;
	OFArray *pathComponents = [[_request IRI] pathComponents];
	isStaticFileRequest = ([pathComponents count] > 1 && [[pathComponents objectAtIndex:1] isEqual:@"static"]);
    return isStaticFileRequest;
}

- (nullable OFData *)requestDataGetter {
    if (requestData != nil)
        return requestData;
    if (_requestBody == nil)
        return nil;
@try {
		requestData = [_requestBody readDataUntilEndOfStream];
} @catch (OFException *ex) {
		return nil;
}
    return requestData;
}

- (BOOL)validateRequest {
	OFArray *pathComponents;
	OFString *path;
@try {
	pathComponents = [[_request IRI] pathComponents];
	path = [[_request IRI] path].pathExtension;
} @catch (OFException *ex) {
	return HTTP_STATUS_400;
}

	for (OFString *comp in pathComponents)
		if ([comp isEqual:@".."] || [comp containsString:@"\\"]) {
			return HTTP_STATUS_400;
		}

	return HANAMI_SUCCESS;
}

- (void)setContentType:(OFString *)contentType {
    // fuck ass framework
    OFMutableDictionary *headers = [_response.headers mutableCopy];
    [headers setObject:contentType forKey:@"Content-Type"];
    _response.headers = headers;
}

- (void)setStatusCode:(int)statusCode {
    _response.statusCode = statusCode;
}

- (void)setHeaders:(OFDictionary *)headers {
    _response.headers = headers;
}

- (void)setObject:(nonnull id)object forKey:(nonnull id)key {
    [_varMap setObject:object forKey:key];
}

- (id)objectForKey:(nonnull id)key {
    return [_varMap objectForKey:key];
}

@end