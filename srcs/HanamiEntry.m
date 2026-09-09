#import "HanamiEntry.h"
#import "HanamiUtils.h"

@implementation HanamiEntry

- (instancetype)initWithIRI:(OFIRI *)iri relativePath:(OFString *)relPath {
    self = [super init];
    if (![[OFFileManager defaultManager] fileExistsAtIRI:iri]) {
        OFLog(@"No file found at %@", iri);
        return nil;
    }
    self->_path = iri;
    self->_relPath = relPath;
    OFFileAttributes attributes = [[OFFileManager defaultManager] attributesOfItemAtIRI:iri];
    self->_modificationDate = [attributes valueForKey:OFFileModificationDate];
    self->_creationDate = [attributes valueForKey:OFFileCreationDate];
    return self;
}

- (OFString *)render:(OFString *)template varMap:(OFDictionary *)varMap {
    OFMutableDictionary *localVarMap = [varMap mutableCopy];
	OFString *contents;
	@try {
		contents = [[OFString alloc] initWithContentsOfIRI:self.path];
	} @catch (OFException *ex) {
		OFLog(@"Got Exception: %@", ex);
		return nil;
	}
    [localVarMap setValue:[OFString stringWithFormat:@"%s", month[self.modificationDate.localMonthOfYear - 1]] forKey:@"$mo"];
    [localVarMap setValue:[OFString stringWithFormat:@"%d", self.modificationDate.localDayOfMonth] forKey:@"$da"];
    [localVarMap setValue:[OFString stringWithFormat:@"%d", self.modificationDate.localYear] forKey:@"$yr"];

	size_t idx = [contents indexOfCharacterFromSet:OFCharacterSet.newlineCharacterSet];

	OFString *first, *rest;
	if (idx != OFNotFound) {
		first = [contents substringWithRange:OFMakeRange(0, idx)];
		rest = [contents substringWithRange:OFMakeRange(idx + 1, contents.length - idx - 1)];
	} else {
		first = contents;
		rest = @"";
	}
	[localVarMap setValue:first forKey:@"$title"];
	[localVarMap setValue:rest forKey:@"$body"];
	[localVarMap setValue:[self.path.lastPathComponent stringByDeletingPathExtension] forKey:@"$fn"];
	// the reason we do the \\ to / is because on windows stringByDeletingLastPathComponent returns the appropriate path component divider for the runtime os
	[localVarMap setValue:[[self.relPath stringByDeletingLastPathComponent] stringByReplacingOccurrencesOfString:@"\\" withString:@"/"] forKey:@"$path"];
    return [HanamiUtils transformTemplate:template varMap:localVarMap];
}

- (OFComparisonResult)compare:(nonnull HanamiEntry *)object {
    return [object.modificationDate compare:self.modificationDate];
}

@end
