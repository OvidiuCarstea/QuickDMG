#import <Cocoa/Cocoa.h>
#import "MDMGWindowController.h"
#import "DMGOptionsViewController.h"
#import "DMGDocument.h"
#import "KXTableView.h"
#import "FileTableController.h"
#import "UtilityFunctions.h"

#define useLog 0

@implementation MDMGWindowController

- (void) dealloc {
#if useLog
	NSLog(@"start dealloc in MDMGWindowController");
#endif	
	[initialItems release];
	[super dealloc];
}

#pragma mark actions
- (IBAction)okAction:(id)sender
{
	if (![[fileListController arrangedObjects] count]) {
		[self showAlertMessage:NSLocalizedString(@"No source items.","") 
				withInformativeText:NSLocalizedString(@"Add some items into the source table.","")];
		return;
	}
	
	NSSavePanel *save_panel = [NSSavePanel savePanel];
	[save_panel setRequiredFileType:[dmgOptionsViewController dmgSuffix]];
	[save_panel setCanSelectHiddenExtension:YES];
	[save_panel beginSheetForDirectory:nil file:nil
				   modalForWindow:[self window]
					modalDelegate:self
				   didEndSelector:@selector(savePanelDidEnd:returnCode:contextInfo:)
					  contextInfo:nil];

}

- (IBAction)addToFileTable:(id)sender
{
	NSOpenPanel *openPanel = [NSOpenPanel openPanel];
	[openPanel setCanChooseDirectories:YES];
	[openPanel setAllowsMultipleSelection:YES];
	[openPanel beginSheetForDirectory:nil 
								 file:nil
								types:nil
					   modalForWindow:[sender window]
						modalDelegate:self
					   didEndSelector:@selector(openPanelDidEnd:returnCode:contextInfo:)
						  contextInfo:nil];
}


#pragma mark delegate sheet
- (void)openPanelDidEnd:(NSOpenPanel *)panel returnCode:(int)returnCode  contextInfo:(void  *)contextInfo
{
	if (returnCode == NSOKButton) {
		[fileTableController addFileURLs:[panel URLs]];
	}
}

- (void)savePanelDidEnd:(NSSavePanel *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo
{
	if (returnCode == NSOKButton) {
		NSString *result_path = [sheet filename];
#if useLog
		NSLog(@"%@", result_path);
#endif
		if (!dmgMaker) {
			[dmgMaker release];
		}
		dmgMaker = [[DiskImageMaker alloc] initWithSourceItems:[fileListController arrangedObjects]];
		[dmgMaker setDMGOptions:dmgOptionsViewController];
		[dmgMaker setDestination:result_path replacing:YES];
		[sheet orderOut:self];
		[self makeDiskImage];
	}
}

#pragma mark setup contents
- (void)setInitialItems:(NSArray *)files
{
	[initialItems autorelease];
	[files retain];
	initialItems = files;
}

- (void)showWindow:(id)sender withFiles:(NSArray *)files
{
	[self setInitialItems:files];
	[self showWindow:sender];
}

- (void)setupFileTable
{
#if useLog	
	NSLog(@"setupFileTable in MDMGWindowController");
#endif
	if (!initialItems) {
		return;
	}
	
	[fileTableController addFileURLs:initialItems];
	

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
	[self autorelease];
}

@end
