#import <ObjFW/ObjFW.h>

@interface HanamiEntry : OFObject <OFComparing> {
	OFIRI *_path;
	OFString *_relPath;
	OFDate *_modificationDate;
	OFDate *_creationDate;
}

- (instancetype)initWithIRI:(OFIRI *)iri relativePath:(OFString *)relPath;
- (OFString *)render:(OFString *)template varMap:(OFDictionary *)varMap;
@property (nonatomic, strong, readonly) OFIRI *path;
@property (nonatomic, strong, readonly) OFString *relPath;
@property (nonatomic, strong, readonly) OFDate *modificationDate;
@property (nonatomic, strong, readonly) OFDate *creationDate;
@end
