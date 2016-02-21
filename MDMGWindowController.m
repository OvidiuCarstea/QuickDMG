#import <Cocoa/Cocoa.h>
#import "MDMGWindowController.h"
#import "DMGOptionsViewController.h"
#import "DMGDocument.h"
#import "KXTableView.h"
#import "FileTableController.h"
#import "UtilityFunctions.h"

#define useLog 0

@implementation MDMGWindowController


#pragma mark actions
- (IBAction)okAction:(id)sender
{
	if (![[fileListController arrangedObjects] count]) {
		[self showAlertMessage:NSLocalizedString(@"No source items.","") 
				withInformativeText:NSLocalizedString(@"Add some items into the source table.","")];
		return;
	}
	
	NSSavePanel *save_panel = [NSSavePanel savePanel];
	[save_panel setAllowedFileTypes:@[[self.dmgOptionsViewController dmgSuffix]]];
	[save_panel setCanSelectHiddenExtension:YES];
    [save_panel beginSheetModalForWindow:self.window
                       completionHandler:^(NSInteger result) {
                           if (result != NSOKButton) return;
                           if (!self.dmgMaker) {
                               self.dmgMaker = nil;;
                           }
                           self.dmgMaker = [[DiskImageMaker alloc] initWithSourceItems:[fileListController arrangedObjects]];
                           self.dmgMaker.dmgOptions = self.dmgOptionsViewController;
                           [self.dmgMaker setDestination:[[save_panel URL] path] replacing:YES];
                           [save_panel orderOut:self];
                           [self makeDiskImage];
                       }];

}

- (IBAction)addToFileTable:(id)sender
{
	NSOpenPanel *openPanel = [NSOpenPanel openPanel];
	[openPanel setCanChooseDirectories:YES];
	[openPanel setAllowsMultipleSelection:YES];

    [openPanel beginSheetModalForWindow:[sender window]
                      completionHandler:^(NSInteger result) {
                          if (result == NSOKButton) {
                              [fileTableController addFileURLs:[openPanel URLs]];
                          }
                      }];
}

#pragma mark setup contents
- (void)showWindow:(id)sender withFiles:(NSArray *)files
{
	self.initialItems = files;
	[self showWindow:sender];
}

- (void)setupFileTable
{
#if useLog	
	NSLog(@"setupFileTable in MDMGWindowController");
#endif
	if (!_initialItems) {
		return;
	}
	
	[fileTableController addFileURLs:_initialItems];
	

	NSRect frame = [splitSubview frame];
	float current_dimension = frame.size.height;
	float row_height = [fileTable rowHeight];
	int nrows = [fileTable numberOfRows];
	NSSize spacing = [fileTable intercellSpacing];
	NSRect hframe =	[[fileTable headerView] frame];
	float scroll_height = [[[fileTable superview] superview] frame].size.height;
	float button_height = current_dimension - scroll_height;
	float table_height = hframe.size.height + ((row_height + spacing.height)*(nrows)) +5;
	float suggested_dimension = table_height + button_height;

	fileTableMinHeight = row_height + hframe.size.height + button_height + spacing.height;
	if (suggested_dimension > current_dimension) suggested_dimension = current_dimension;
	[splitView setPosition:suggested_dimension ofDividerAtIndex:0];
}

- (CGFloat)splitView:(NSSplitView *)sender constrainMinCoordinate:(CGFloat)proposedMin ofSubviewAt:(NSInteger)offset
{
	if (offset == 0) {
		proposedMin = fileTableMinHeight;
	}
	return proposedMin;
}


#pragma mark delegate of KXTabelView

- (IBAction)deleteTabelSelection:(id)sender
{
	NSArray *selected_items = [fileListController selectedObjects];
	//[fileListController remove:self];
	[fileListController removeObjects:selected_items];
	NSEnumerator *enumerator = [selected_items objectEnumerator];
	DMGDocument *a_source;
	while (a_source = [enumerator nextObject]) {
		[a_source setIsMultiSourceMember:NO];
		[a_source dispose:self];
	}
}

- (void)openTableSelection:(id)sender
{
	NSArray *selected_items = [fileListController selectedObjects];	
	NSEnumerator *enumerator = [selected_items objectEnumerator];
	DMGDocument *a_source;
	while (a_source = [enumerator nextObject]) {
		if (![[a_source windowControllers] count]) {
			[a_source makeWindowControllers];
		}
		[a_source showWindows];
	}
}

#pragma mark override NSWindowController
- (void)windowDidLoad
{
	[fileTable setDeleteAction:@selector(deleteTabelSelection:)];
	[fileTable setDoubleAction:@selector(openTableSelection:)];
	[self setupFileTable];
}

- (void)awakeFromNib
{
	#if useLog
	NSLog(@"awakeFromNib in MDMGWindowController");
	#endif
	[super awakeFromNib];
}

#pragma mark delegate of NSWindow
- (void)windowWillClose:(NSNotification *)aNotification
{
	[fileTableController disposeDocuments];
	[[self dmgOptionsViewController] saveSettings];
}

@end
