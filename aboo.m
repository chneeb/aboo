#import <Foundation/Foundation.h>
#import <AddressBook/AddressBook.h>

#import "RegexKitLite.h"

#include <unistd.h>


/* TODO:
 * - YAML Import
 * - vCard Import
 * - getopt()
 *   - -f <file>, YAML or vCard
 */

#define OPTION_FORMAT     "  %s %s\t%s\n" /* Ausgabeformat fuer usage() */
#define CAPTUREVECTORSIZE 30              /* muss Mehrfaches von 3 sein */

void usage();
void print_person(ABPerson *person);
void print_person_vcf(ABPerson *person);
void print_person_yml(ABPerson *person);
void print_person_pine(ABPerson *person);
BOOL match_person(ABPerson *person, NSString *searchTerm);
BOOL match_person_regex(ABPerson *person, const char *pattern);
BOOL match_regex(const char *text, const char *pattern);
void import_data(NSData *inputData);
void update_data(NSData *inputData);
ABPerson *find_person(ABPerson *person);
NSArray *read_people(NSData *inputData);
void write_birthdays();

int main (int argc, const char * argv[]) {
    NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];

	// getopt
	int ch;
	char *optSearchTerm     = NULL;
	char *optSearchRegex    = NULL;
	BOOL  shouldSearchTerm  = NO;
	BOOL  shouldSearchRegex = NO;
	BOOL  shouldOutputVcf   = NO;
	BOOL  shouldOutputYml   = NO;
	BOOL  shouldOutputPine  = NO;
	BOOL  shouldImportVcf   = NO;
	BOOL  shouldWriteBdays  = NO;
	
	while ((ch = getopt(argc, (char * const *) argv, "hs:r:vypib")) != -1)
	{
		switch(ch)
		{
			case 'b':
					shouldWriteBdays = YES;
			case 's':
					optSearchTerm = optarg;
					shouldSearchTerm = YES;
					shouldSearchRegex = NO;
					break;
			case 'r':
					optSearchRegex = optarg;
					shouldSearchRegex = YES;
					shouldSearchTerm = NO;
					break;
			case 'v':
					shouldOutputVcf = YES;
					break;
			case 'y':
					shouldOutputYml = YES;
					break;
			case 'p':
					shouldOutputPine = YES;
					break;
			case 'i':
					shouldImportVcf = YES;
					break;
			case 'h':
					usage();
					break;
		}
	}
	argc -= optind;
	argv += optind;
	
	// write the birthdays file for all persons
	if(shouldWriteBdays)
	{
		write_birthdays();
		exit(0);
	}

	// import vcf -> AddressBook.app must be configured with UTF-8 Import/Export
	if(shouldImportVcf)
	{
		NSData* inputData = [[NSFileHandle fileHandleWithStandardInput] readDataToEndOfFile];
		import_data(inputData);
		exit(0);
	}
	
	// getting address book and the people array
	ABAddressBook *abook = [ABAddressBook sharedAddressBook];
	NSArray *people = [abook people];
	NSEnumerator *enumerator = [people objectEnumerator];
	ABPerson *person;

	if(shouldOutputYml) printf("--- # YAML 1.0\n");
	
	while(person = [enumerator nextObject])
	{
		BOOL recordMatches = NO;

		if(shouldSearchTerm)
		{	
			NSString *searchTerm = [[NSString alloc] initWithUTF8String:optSearchTerm];
			recordMatches = match_person(person, searchTerm);
		}
		else if(shouldSearchRegex)
		{
			recordMatches = match_person_regex(person, optSearchRegex);
		}
				
		if(!(shouldSearchTerm || shouldSearchRegex) || recordMatches)
		{
			if(shouldOutputVcf)
			{
				print_person_vcf(person);
			}
			else if(shouldOutputYml)
			{
				print_person_yml(person);
			}
			else if(shouldOutputPine)
			{
				print_person_pine(person);
			}
			else
			{
				print_person(person);
			}
		}
	}
	
	[pool release];
    return 0;
}

void write_birthdays()
{
	// getting address book and the people array
	ABAddressBook *abook = [ABAddressBook sharedAddressBook];
	NSArray *people = [abook people];
	NSEnumerator *enumerator = [people objectEnumerator];
	ABPerson *person;

	NSString *bdaysPath = [@"~/Library/Calendars/Birthdays.ics" stringByExpandingTildeInPath];
	NSString *ics = @"BEGIN:VCALENDAR\nVERSION:2.0\nX-WR-CALNAME:Birthdays\nX-WR-CALDESC:created by aboo\nX-WR-TIMEZONE:Europe/Berlin\nCALSCALE:GREGORIAN\n";
	
	while(person = [enumerator nextObject])	
	{
		NSDate *bday = [person valueForProperty:kABBirthdayProperty];
		
		if(!bday) continue;
		
		NSString *bdayString = [bday descriptionWithCalendarFormat:@"%Y%m%d" timeZone:nil locale:nil];
		NSString *dayAfterString = [[bday addTimeInterval:60*60*24] descriptionWithCalendarFormat:@"%Y%m%d" timeZone:nil locale:nil]; 

		ics = [ics stringByAppendingString:@"BEGIN:VEVENT\n"];
		ics = [ics stringByAppendingFormat:@"DTSTART;VALUE=DATE:%s\n", [bdayString UTF8String]];
		ics = [ics stringByAppendingFormat:@"DTEND;VALUE=DATE:%s\n", [dayAfterString UTF8String]];
		ics = [ics stringByAppendingFormat:@"SUMMARY:%s %s\n",
			[[person valueForProperty:kABFirstNameProperty] UTF8String],
			[[person valueForProperty:kABLastNameProperty]  UTF8String] ];
		ics = [ics stringByAppendingFormat:@"SEQUENCE:%i\n", 3];
		ics = [ics stringByAppendingString:@"RRULE:FREQ=YEARLY;INTERVAL=1\n"];
		ics = [ics stringByAppendingString:@"BEGIN:VALARM\nTRIGGER:-P1D\nDESCRIPTION:Birthday\nACTION:DISPLAY\nEND:VALARM\nEND:VEVENT\n"];
	}
	
	ics = [ics stringByAppendingString:@"END:VCALENDAR\n"];
	[ics writeToFile:bdaysPath atomically:YES];
	[ics release];
}

BOOL match_person(ABPerson *person, NSString *searchTerm)
{
	ABSearchElement *lastNameSearch = [ABPerson searchElementForProperty:kABLastNameProperty
												  label:nil
													key:nil
												  value:searchTerm
											 comparison:kABEqualCaseInsensitive];
	ABSearchElement *firstNameSearch = [ABPerson searchElementForProperty:kABFirstNameProperty
												   label:nil
													 key:nil
												   value:searchTerm
											  comparison:kABEqualCaseInsensitive];
	ABSearchElement *nickNameSearch =  [ABPerson searchElementForProperty:kABNicknameProperty
												   label:nil
													 key:nil
												   value:searchTerm
											  comparison:kABEqualCaseInsensitive];
	
	BOOL recordMatches = (	[lastNameSearch matchesRecord:person]	||
							[firstNameSearch matchesRecord:person]	||
							[nickNameSearch matchesRecord:person]	);

	return recordMatches;
}

BOOL match_person_regex(ABPerson *person, const char *pattern)
{
	const char *lastName  = [[person valueForProperty:kABLastNameProperty] UTF8String];
	const char *firstName = [[person valueForProperty:kABFirstNameProperty] UTF8String];
	const char *nickName  = [[person valueForProperty:kABNicknameProperty] UTF8String];
	
	if(nickName != NULL && match_regex(nickName, pattern))
	{
		return YES;
	}
	else if(lastName != NULL && match_regex(lastName, pattern))
	{
		return YES;
	}
	else if(firstName != NULL && match_regex(firstName, pattern))
	{
		return YES;
	}
	
	return NO;
}

BOOL match_regex(const char *text, const char *pattern)
{
	NSString *source = [[NSString alloc] initWithCString:text];
	NSString *regex = [[NSString alloc] initWithCString:pattern];
	
	NSString *match = [source stringByMatching:regex];
	
	if(match == NULL)
	{
		return NO;
	}
	else
	{
		return YES;	
	}
}

void print_person_vcf(ABPerson *person)
{
	NSData *vCardData = [person vCardRepresentation];
	NSString *vCardString = [[NSString alloc] initWithData:vCardData encoding:NSUTF8StringEncoding];
	if(vCardString == nil)
	{
		[vCardString release];
		vCardString = [[NSString alloc] initWithData:vCardData encoding:NSUnicodeStringEncoding];
	}
	printf("%s", [vCardString UTF8String]);
	[vCardString release];
}

void print_person_yml(ABPerson *person)
{
	NSArray *properties = [ABPerson properties];
	NSEnumerator *it = [properties objectEnumerator];
	NSString *property;
	
	printf("-\n"); 
	
	while(property = [it nextObject])
	{	
		ABPropertyType type = [ABPerson typeOfProperty:property];
		
		if(type == kABStringProperty)
		{
			NSString *string = [person valueForProperty:property];
			if(string != nil) printf("  %s: %s\n", [property UTF8String], [string UTF8String]);
		}
		else if(type == kABDateProperty)
		{
			NSCalendarDate *date = [person valueForProperty:property];
			if(date != nil) printf("  %s: %s\n", [property UTF8String], [[date description] UTF8String]);		
		}
		else if(type == kABMultiStringProperty)
		{
			ABMultiValue *multiValue = [person valueForProperty:property];
			if(multiValue != nil)
			{
				NSString *primaryIdentifier = [multiValue primaryIdentifier];
				if(primaryIdentifier != nil)
				{
					NSString *primaryValue = [multiValue valueAtIndex:[multiValue indexForIdentifier:primaryIdentifier]];
					if(primaryValue != nil) printf("  %s: %s\n", [property UTF8String], [primaryValue UTF8String]);	
				}
			}
		}
	}
}

void print_person_pine(ABPerson *person)
{
	NSString *nickName  = [person valueForProperty:kABNicknameProperty];
	NSString *lastName  = [person valueForProperty:kABLastNameProperty];
	NSString *firstName = [person valueForProperty:kABFirstNameProperty]; 
	ABMultiValue *email = [person valueForProperty:kABEmailProperty];
	NSString *primaryEmail = [email valueAtIndex:[email indexForIdentifier:[email primaryIdentifier]]];

	NSString *usedAlias;
	NSString *formattedOutput = [[[NSString alloc] init] autorelease];
	
	/* mail alias for pine addressbook */
	if(nickName != nil)
	{
		usedAlias = [nickName lowercaseString];
	}
	else if(lastName != nil)
	{
		/* create eight character login string like: Christian Neeb -> neebchri
		 * at least one character of the first name should be used if it exists
		 */
		usedAlias = [lastName lowercaseString];
		if([usedAlias length] > 7 && firstName != nil)
		{
			NSRange loginRange = NSMakeRange(0,7);
			usedAlias = [usedAlias substringWithRange:loginRange];
		}
		else if([usedAlias length] > 8 && firstName == nil)
		{
			NSRange loginRange = NSMakeRange(0,8);
			usedAlias = [usedAlias substringWithRange:loginRange];		
		}
		
		if(firstName != nil)
		{
			int max_length = 8 - [usedAlias length];
			if([firstName length] < max_length) max_length = [firstName length];
			
			NSRange loginRange = NSMakeRange(0, max_length);
			usedAlias = [usedAlias stringByAppendingString:[[firstName lowercaseString] substringWithRange:loginRange]];
		}
	}
	else
	{
		return; /* don't output a person without nickname or first name */
	}

	formattedOutput = [formattedOutput stringByAppendingFormat:@"%@", usedAlias];

	/* full name for pine addressbook */
	if((firstName != nil) && (lastName != nil))
	{
		formattedOutput = [formattedOutput stringByAppendingFormat:@"\t%@ %@", firstName, lastName];
	}
	else if((firstName == nil) && (lastName != nil))
	{
		formattedOutput = [formattedOutput stringByAppendingFormat:@"\t%@", lastName];
	}
	else
	{
		return; /* don't output a person without a last name */
	}

	/* mail address for pine addressbook */
	if(primaryEmail != nil)
	{
		formattedOutput = [formattedOutput stringByAppendingFormat:@"\t%@", primaryEmail];
	}
	else
	{
		return; /* don't output a person without mail address */
	}
	
	/* mail folder name for pine */
	/* comment for pine addressbook */
	
	printf("%s\n", [formattedOutput UTF8String]);
}

void print_person(ABPerson *person)
{
	NSString *lastName  = [person valueForProperty:kABLastNameProperty];
	NSString *firstName = [person valueForProperty:kABFirstNameProperty]; 
	ABMultiValue *phone = [person valueForProperty:kABPhoneProperty];
	ABMultiValue *email = [person valueForProperty:kABEmailProperty];
	
	NSString *primaryPhone = [phone valueAtIndex:[phone indexForIdentifier:[phone primaryIdentifier]]];
	NSString *primaryEmail = [email valueAtIndex:[email indexForIdentifier:[email primaryIdentifier]]];
	
	NSString *formattedOutput = [[NSString alloc] initWithFormat:@"%@ %@", firstName, lastName];
	
	if(primaryEmail != nil)
	{
		formattedOutput = [formattedOutput stringByAppendingFormat:@" <%@>", primaryEmail];
	}
	if(primaryPhone != nil)
	{
		formattedOutput = [formattedOutput stringByAppendingFormat:@": %@", primaryPhone];
	}
	
	printf("%s\n", [formattedOutput UTF8String]);
}

NSArray *read_people(NSData *inputData)
{
	NSMutableArray *people = [[[NSMutableArray alloc] init] autorelease];
	NSString *inputString = [[NSString alloc] initWithData:inputData encoding:NSUTF8StringEncoding];
	NSArray *cards = [inputString componentsSeparatedByString:@"END:VCARD\r\n"];
	NSEnumerator *it = [cards objectEnumerator];
	NSString *component;

	while(component = [it nextObject])
	{
		if([component isEqualToString:@""] || [component hasPrefix:@"\r\n"] || [component hasPrefix:@"\n"]) continue;
		NSString *card = [[NSString alloc] initWithFormat:@"%@%@", component, @"END:VCARD\r\n"];
		NSData *cardData = [card dataUsingEncoding:NSUTF8StringEncoding];
		ABPerson *newPerson = [[ABPerson alloc] initWithVCardRepresentation:cardData];
		if(newPerson != nil) [people addObject:newPerson];
		
		[card release];
	}
	
	[inputString release];
	[cards release];
	
	return people;
}

void import_data(NSData *inputData)
{
	ABAddressBook *abook = [ABAddressBook sharedAddressBook];
	NSArray *newPeople = read_people(inputData);
	NSEnumerator *it = [newPeople objectEnumerator];
	ABPerson *newPerson;

	while(newPerson = [it nextObject])
	{		
		if(find_person(newPerson) == nil)
		{
			NSLog(@"adding %@, %@", [newPerson valueForProperty:kABLastNameProperty], [newPerson valueForProperty:kABFirstNameProperty]);
/*		
			if([abook addRecord:newPerson])
			{
				[abook save];
			}
*/
		}
		else
		{
			NSLog(@"person %@, %@ does already exist!", [newPerson valueForProperty:kABLastNameProperty], [newPerson valueForProperty:kABFirstNameProperty]);
		}
	}
}

void update_data(NSData *inputData)
{

}

ABPerson *find_person(ABPerson *person)
{
	NSString *lastName  = [person valueForProperty:kABLastNameProperty];
	NSString *firstName = [person valueForProperty:kABFirstNameProperty]; 	

	ABSearchElement *lastNameSearch = [ABPerson searchElementForProperty:kABLastNameProperty
																   label:nil
																	 key:nil
																   value:lastName
															  comparison:kABEqualCaseInsensitive];
	ABSearchElement *firstNameSearch = [ABPerson searchElementForProperty:kABFirstNameProperty
																	label:nil
																	  key:nil
																	value:firstName
															   comparison:kABEqualCaseInsensitive];

	ABAddressBook *abook = [ABAddressBook sharedAddressBook];
	NSArray *people = [abook people];
	NSEnumerator *it = [people objectEnumerator];
	ABPerson *activePerson;

	while(activePerson = [it nextObject])
	{
		BOOL recordMatches = (	[lastNameSearch matchesRecord:activePerson]	    &&
								[firstNameSearch matchesRecord:activePerson]	);
		if(recordMatches) return activePerson;
	}
	
	return nil;
}

void usage()
{
	printf("usage: %s [options]\n", "aboo");
	printf(OPTION_FORMAT, "-s", "<search term>", "search for term in first-, last- and nickname");
	printf(OPTION_FORMAT, "-r", "<search regex>", "search for regex in first-, last- and nickname");
	printf(OPTION_FORMAT, "-v", "\t\t", "vCard 3.0 output");
	printf(OPTION_FORMAT, "-v", "\t\t", "YAML 1.0 output");
	printf(OPTION_FORMAT, "-p", "\t\t", "Pine addressbook output (~/.addressbook)");
	printf(OPTION_FORMAT, "-h", "\t\t", "this help screen");
	exit(1);
}

