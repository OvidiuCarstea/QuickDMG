#import "ExpandDMGWindowController.h"
#import "PathExtra.h"
#import "StringExtra.h"

@implementation ExpandDMGWindowController

@synthesize dmgHandler;
@synthesize dmgPath;

- (void)dealloc
{
	[dmgHandler release];
	[dmgPath release];
	[super dealloc];
}

- (void)processFile:(NSString *)path
{
	self.dmgPath = path;
	DMGHandler *h = [DMGHandler dmgHandlerWithDelegate:self];
	[self showWindow:self];
	//[self.window setTitleWithRepresentedFilename:path];
	[self.window setRepresentedFilename:path];
	NSString *title = [NSString stringWithLocalizedFormat:@"Expanding %@", 
						[path lastPathComponent]];
	[self.window setTitle:title];
	[progressIndicator startAnimation:self];
	[h attachDiskImage:path];
	self.dmgHandler = h;
}

- (void)diskImageDetached:(DMGHandler *)sender
{
	if (sender.terminationStatus != 0) {
		dmgHandler.statusMessage = [NSString stringWithLocalizedFormat:@"Failed detaching with error : %@",
															sender.terminationMessage];
		return;
	}
	[progressIndicator stopAnimation:self];
	[self close];
}

- (void)dittoFinished:(DMGHandler *)sender
{
	if (sender.terminationStatus != 0) {
		dmgHandler.statusMessage = [NSString stringWithLocalizedFormat:@"Failed copy with error : %@",
															sender.terminationMessage];
		[sender detachNow];
		return;
	}
	[sender detachDiskImage:nil];
}

- (void)diskImageAttached:(DMGHandler *)sender
{
	if (sender.terminationStatus != 0) {
		dmgHandler.statusMessage = [NSString stringWithLocalizedFormat:@"Failed attaching with error : %@",
										sender.terminationMessage];
		return;
	}
	NSString *src = sender.mountPoint;
	NSString *dest_dir = [dmgPath stringByDeletingLastPathComponent];
	NSString *uname = [[src lastPathComponent] uniqueNameAtLocation:dest_dir];
	NSString *dest_path = [dest_dir stringByAppendingPathComponent:uname];
	[sender dittoPath:sender.mountPoint toPath:dest_path];
}

- (IBAction)cancelTask:(id)sender
{
	[dmgHandler abortTask];
	[progressIndicator stopAnimation:self];
	[self close];
}

@end
