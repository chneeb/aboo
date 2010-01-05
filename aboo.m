#import <Foundation/Foundation.h>
#import <AddressBook/AddressBook.h>
#import "RegexKitLite.h"
#include <unistd.h>

#define OPTION_FORMAT     "  %s %s\t%s\n" /* Ausgabeformat fuer usage() */

void usage();
void print_person(ABPerson *person);
void print_person_vcf(ABPerson *person);
void print_person_ics(ABPerson *person);
void print_person_yml(ABPerson *person);
void print_person_mutt(ABPerson *person);
BOOL match_person_regex(ABPerson *person, NSString *pattern);
BOOL match_regex(NSString *text, NSString *pattern);
void import_data(NSData *inputData);
void update_data(NSData *inputData);
ABPerson *find_person(ABPerson *person);
NSArray *read_people(NSData *inputData);

int main (int argc, const char * argv[]) {
    NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];

	// getopt
	int ch;
	char *optSearchTerm     = NULL;
	BOOL  shouldSearchTerm  = NO;
	BOOL  shouldOutputVcf   = NO;
	BOOL  shouldOutputIcs   = NO;
	BOOL  shouldOutputYml   = NO;
	BOOL  shouldOutputMutt  = NO;
	BOOL  shouldImportVcf   = NO;
	
	while ((ch = getopt(argc, (char * const *) argv, "hs:mvyb")) != -1)
	{
		switch(ch)
		{
			case 'b':
					shouldOutputIcs = YES;
					break;
			case 's':
					optSearchTerm = optarg;
					shouldSearchTerm = YES;
					break;
			case 'm':
					shouldOutputMutt = YES;
					break;
			case 'v':
					shouldOutputVcf = YES;
					break;
			case 'y':
					shouldOutputYml = YES;
					break;
			case 'h':
					usage();
					break;
		}
	}
	argc -= optind;
	argv += optind;
	
	// getting address book and the people array
	ABAddressBook *abook = [ABAddressBook sharedAddressBook];
	NSArray *people = [abook people];
	NSEnumerator *enumerator = [people objectEnumerator];
	ABPerson *person;
	NSString *regex = @"";
	if(optSearchTerm != NULL)
	{
		regex = [[[NSString alloc] initWithUTF8String:optSearchTerm] stringByReplacingOccurrencesOfString:@" " withString:@""];
	}
		
	if(shouldOutputYml) printf("--- # YAML 1.0\n");
	if(shouldOutputMutt) printf("Search term: '%s'\n", [regex UTF8String]);
	if(shouldOutputIcs) printf("BEGIN:VCALENDAR\nVERSION:2.0\nX-WR-CALNAME:Birthdays\nX-WR-CALDESC:created by aboo\nX-WR-TIMEZONE:Europe/Berlin\nCALSCALE:GREGORIAN\n");
	
	while(person = [enumerator nextObject])
	{
		BOOL recordMatches = NO;

		if(shouldSearchTerm && match_person_regex(person, regex))
		{	
			recordMatches = YES;
		}
				
		if(!shouldSearchTerm || recordMatches)
		{
			if(shouldOutputVcf)
			{
				print_person_vcf(person);
			}
			else if(shouldOutputIcs)
			{
				print_person_ics(person);
			}
			else if(shouldOutputYml)
			{
				print_person_yml(person);
			}
			else if(shouldOutputMutt)
			{
				print_person_mutt(person);
			}
			else
			{
				print_person(person);
			}
		}
	}
	
	if(shouldOutputIcs) printf("END:VCALENDAR\n");
	
	[pool release];
    return 0;
}

BOOL match_person_regex(ABPerson *person, NSString *pattern)
{
	NSString *lastName  = [person valueForProperty:kABLastNameProperty];
	NSString *firstName = [person valueForProperty:kABFirstNameProperty];
	NSString *nickName  = [person valueForProperty:kABNicknameProperty];
	
	if(match_regex(nickName, pattern) || match_regex(lastName, pattern) || match_regex(firstName, pattern))
		return YES;
	else
		return NO;
}

BOOL match_regex(NSString *text, NSString *pattern)
{
	NSRange range = NSMakeRange(0, [text length]);
	NSError *error = NULL;
	NSString *match = [text stringByMatching:pattern options:RKLCaseless inRange:range capture:0 error:&error];
	
	if(text != NULL && match != NULL)
		return YES;
	else
		return NO;
}

void print_person_ics(ABPerson *person)
{
	NSString *ics = @"";
	NSDate *bday = [person valueForProperty:kABBirthdayProperty];
	
	if(!bday) return;
	
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

	printf("%s", [ics UTF8String]);
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

void print_person_mutt(ABPerson *person)
{
	NSString *lastName  = [person valueForProperty:kABLastNameProperty];
	NSString *firstName = [person valueForProperty:kABFirstNameProperty]; 
	ABMultiValue *email = [person valueForProperty:kABEmailProperty];
	NSString *primaryEmail = [email valueAtIndex:[email indexForIdentifier:[email primaryIdentifier]]];
	
	NSString *formattedOutput = [NSString stringWithFormat:@"%@\t%@ %@", primaryEmail, firstName, lastName];
	
	if(primaryEmail == nil)
		return; /* don't output a person without mail address */

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

void usage()
{
	printf("usage: %s [options]\n", "aboo");
	printf(OPTION_FORMAT, "-s", "<search term>", "search for term in first-, last- and nickname");
	printf(OPTION_FORMAT, "-v", "\t\t", "vCard 3.0 output");
	printf(OPTION_FORMAT, "-y", "\t\t", "YAML 1.0 output");
	printf(OPTION_FORMAT, "-b", "\t\t", "ics birthday calendar output");
	printf(OPTION_FORMAT, "-m", "\t\t", "Mutt address book output");
	printf(OPTION_FORMAT, "-h", "\t\t", "this help screen");
	exit(1);
}

