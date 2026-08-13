// foldertop_hook.m — keeps folders on top in Finder for any sort order:
// overrides the private -shouldSortFoldersFirstForSortBy:groupBy: to return
// YES. Loaded via DYLD_INSERT_LIBRARIES (global), so the constructor
// self-filters by bundle id and bails out outside Finder.

#import <Foundation/Foundation.h>
#import <objc/runtime.h>

static BOOL foldertop_always_yes(id self, SEL _cmd, ...) { return YES; }

__attribute__((constructor))
static void foldertop_init(void) {
    @autoreleasepool {
        if (![NSBundle.mainBundle.bundleIdentifier
                isEqualToString:@"com.apple.finder"]) {
            return;
        }

        SEL sel = @selector(shouldSortFoldersFirstForSortBy:groupBy:);
        unsigned int classCount = 0;
        Class *classes = objc_copyClassList(&classCount);
        int hooked = 0;

        for (unsigned int i = 0; i < classCount; i++) {
            unsigned int methodCount = 0;
            Method *methods = class_copyMethodList(classes[i], &methodCount);
            for (unsigned int j = 0; j < methodCount; j++) {
                if (method_getName(methods[j]) == sel) {
                    method_setImplementation(methods[j],
                                             (IMP)foldertop_always_yes);
                    hooked++;
                }
            }
            free(methods);
        }
        free(classes);

        if (hooked == 0) {
            NSLog(@"[foldertop] selector shouldSortFoldersFirstForSortBy:groupBy: "
                  @"not found — did Finder change? hook inactive");
        } else {
            NSLog(@"[foldertop] active, classes hooked: %d", hooked);
        }
    }
}
