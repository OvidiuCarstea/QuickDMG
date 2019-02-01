#import "DMGWindowController.h"
#import "DMGDocument.h"
#import "DMGOptionsViewController.h"
#import "AppController.h"
#import "DMGProgressWindowController.h"

#define useLog 1

#ifdef SANDBOX
#else
#define SANDBOX 0
#endif

@implementation DMGWindowController

#pragma mark methods for sheet
- (void)alertDidEnd:(NSWindow*)alert returnCode:(int)returnCode contextInfo:(void *)contextInfo //common
{
}

- (void)showAlertMessage:(NSString *)theMessageText withInformativeText:(NSString *)infoText
{
	NSWindow *window = [self window];
	
	NSWindow *sheet = [window attachedSheet];
	if (sheet != nil) {
		[[NSApplication sharedApplication] endSheet:sheet returnCode:DIALOG_ABORT];
	}

	NSAlert *alert = [[NSAlert alloc] init];
	[alert addButtonWithTitle:@"OK"];
	[alert setMessageText:theMessageText];
	[alert setInformativeText:infoText];
	
	[alert beginSheetModalForWindow:window modalDelegate:self 
			didEndSelector:@selector(alertDidEnd:returnCode:contextInfo:) contextInfo:nil];
}

- (IBAction)chooseTargetPath:(id)sender //not common
{
	NSSavePanel *savePanel = [NSSavePanel savePanel];
	[savePanel setAllowedFileTypes:@[[_dmgOptionsViewController dmgSuffix]]];
	[savePanel setCanSelectHiddenExtension:YES];
    [savePanel setDirectoryURL:_dmgMaker.workingLocationURL];
    [savePanel setNameFieldStringValue:[_dmgMaker dmgName]];
    [savePanel beginSheetModalForWindow:self.window
                      completionHandler:^(NSInteger result){
                          if (result == NSOKButton) {
                              NSURL *result_url = [savePanel URL];
                              _dmgMaker.workingLocationURL = [result_url URLByDeletingLastPathComponent];
                              [_dmgMaker setCustomDmgName:[result_url lastPathComponent]];
                              [self setTargetPath:[_dmgMaker dmgPath]];
                              if (SANDBOX && okButtonPushed) {
                                  [self makeDiskImage];
                                  okButtonPushed = NO;
                              }
                          }
                      }];
}


- (void)sheetDidEnd:(NSWindow*)sheet returnCode:(int)returnCode contextInfo:(void*)contextInfo
{
    [sheet orderOut:self];
    
    // Check return code
    if(returnCode == DIALOG_ABORT) {
        // Cancel button was pushed
        //NSLog(@"Sheet is canceled");
        return;
    }
    else if(returnCode == DIALOG_OK) {
        // OK button was pushed
        //NSLog(@"Sheet is accepted");
    }
}

#pragma mark methods for setup
- (void)setupProgressWindow //common
{
	if (!_progressWindowController) {
		self.progressWindowController = [[DMGProgressWindowController alloc] initWithNibName:@"DMGProgressWindow"];
	}
	[_progressWindowController beginSheetWith:self];
}

- (void)setTargetPath:(NSString *)string // not common
{
    if (string) {
        [targetPathView setStringValue:string];
    }
}

- (void)setupDMGOptionsView //common
{
#if useLog
    NSLog(@"%@", @"start setupDMGOptionsView");
#endif
    self.dmgOptionsViewController = [[DMGOptionsViewController alloc]
								initWithNibName:@"DMGOptionsView" owner:self];
	[dmgOptionsBox setContentView:[_dmgOptionsViewController view]];
	[okButton bind:@"enabled" toObject:[_dmgOptionsViewController dmgFormatController]
								withKeyPath:@"selectedObjects.@count" options:nil];
	[[_dmgOptionsViewController tableView] setDoubleAction:@selector(okAction:)];
}

#pragma mark communicate with DiskImageMaker
- (void)makeDiskImage //common
{
	[self setupProgressWindow];
	if ([_dmgMaker checkCondition:self]) {
        
		NSNotificationCenter* notification_center = [NSNotificationCenter defaultCenter];
		[notification_center addObserver:_progressWindowController
							   selector:@selector(showStatusMessage:)
								   name:@"DmgProgressNotification"
								 object:_dmgMaker];
        
        [_dmgMaker createDiskImageWithCompletaionHandler:^(BOOL result){
            if (result) {
                NSWindow *window = [self window];
                NSWindow *sheet = [window attachedSheet];
                
                if (sheet != nil) {
                    [[NSApplication sharedApplication] endSheet:sheet returnCode:DIALOG_OK];
                }
                [_dmgOptionsViewController saveSettings];
                [self close];
            }
            else {
                NSString *a_message = _dmgMaker.terminationMessage;
                [self showAlertMessage:NSLocalizedString(@"Error! Can't progress jobs.","")
                   withInformativeText:a_message];
            }
        }];
	}
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object //not common
				change:(NSDictionary *)change context:(void *)context
{
    if ([keyPath isEqual:@"selectedObjects"]) {
		[_dmgMaker resolveDmgName];
		[targetPathView setStringValue:[_dmgMaker dmgPath]];
    }
}

-(void) dmgDidTerminate:(NSNotification *) notification //common deprecated
{	
#if useLog
    NSLog(@"%@", @"start dmgDidTerminate");
#endif
    DiskImageMaker *dmg_maker = [notification object];

	if ([dmg_maker terminationStatus] == 0) {
		NSWindow *window = [self window];
		NSWindow *sheet = [window attachedSheet];

		if (sheet != nil) {
			[[NSApplication sharedApplication] endSheet:sheet returnCode:DIALOG_OK];
		}
		[_dmgOptionsViewController saveSettings];
		[self close];
	}
	else {
#if useLog
		NSLog(@"termination status is not 0");
#endif		
		NSString *a_message = [dmg_maker terminationMessage];
		[self showAlertMessage:NSLocalizedString(@"Error! Can't progress jobs.","") 
								withInformativeText:a_message];
	}
	
	NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
	[notificationCenter removeObserver:self];
}

#pragma mark delegate of NSWindow
- (void)windowWillClose:(NSNotification *)aNotification
{
	[[_dmgOptionsViewController dmgFormatController] removeObserver:self
													forKeyPath:@"selectedObjects"];
}

#pragma mark action
- (IBAction)cancelAction:(id)sender //common 
{
	[[self window] performClose:self];
}

- (IBAction)okAction:(id)sender //not common
{
    if (SANDBOX && ! _dmgMaker.isReplacing) {
        okButtonPushed = YES;
        [self chooseTargetPath:self];
    } else {
        [self makeDiskImage];
    }
}

#pragma mark initialize

- (void)windowDidLoad
{
	[[_dmgOptionsViewController dmgFormatController] addObserver:self
							 forKeyPath:@"selectedObjects"
								 options:(NSKeyValueObservingOptionNew)
									context:NULL];
					
	
	id theDocument = [self document];

	[sourcePathView setStringValue:[[theDocument fileURL] path]];
	self.dmgMaker = [[DiskImageMaker alloc] initWithSourceItem:theDocument];
	_dmgMaker.dmgOptions = _dmgOptionsViewController;
	[targetPathView setStringValue:[_dmgMaker dmgPath]];
}

NSValue *lefttop_of_frame(NSRect aRect)
{
	return [NSValue valueWithPoint:NSMakePoint(NSMinX(aRect), NSMaxY(aRect))];
}

- (void)awakeFromNib
{
#if useLog
    NSLog(@"awakeFromNib in DMGWindowController");
#endif
    okButtonPushed = NO;
	[self setupDMGOptionsView];	
	[[self window] center];
	NSValue *current_lt = lefttop_of_frame([[self window] frame]);
	NSMutableArray *left_tops = [NSMutableArray array];
	NSRect a_frame;
	for (NSWindow *a_window in [NSApp windows]) {
		if ([a_window isVisible]) {
			a_frame = [a_window frame];
			[left_tops addObject:lefttop_of_frame(a_frame)];
		}	
	}
	
	if ([left_tops count]) {
		while(1) {		
			if ([left_tops containsObject:current_lt]) {
				current_lt = [NSValue valueWithPoint:
								[[self window] cascadeTopLeftFromPoint:[current_lt pointValue]]];
			} else {
				break;
			}
		}
		[[self window] setFrameTopLeftPoint:[current_lt pointValue]];
	}
}

@end
