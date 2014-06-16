//
//  NSTextView+Autocomplete.m
//  MacDown
//
//  Created by Tzu-ping Chung  on 11/06/2014.
//  Copyright (c) 2014 Tzu-ping Chung . All rights reserved.
//

#import "NSTextView+Autocomplete.h"
#import "NSString+Lookup.h"
#import "MPUtilities.h"


static const unichar kMPMatchingCharactersMap[][2] = {
    {L'(', L')'},
    {L'[', L']'},
    {L'{', L'}'},
    {L'<', L'>'},
    {L'\'', L'\''},
    {L'\"', L'\"'},
    {L'\uff08', L'\uff09'},     // full-width parentheses
    {L'\u300c', L'\u300d'},     // corner brackets
    {L'\u300e', L'\u300f'},     // white corner brackets
    {L'\u2018', L'\u2019'},     // single quotes
    {L'\u201c', L'\u201d'},     // double quotes
    {L'\0', L'\0'},
};

static const unichar kMPStrikethroughCharacter = L'~';

static const unichar kMPMarkupCharacters[] = {
    L'*', L'_', L'`', L'=', L'\0',
};


@implementation NSTextView (Autocomplete)

- (BOOL)substringInRange:(NSRange)range isSurroundedByPrefix:(NSString *)prefix
                  suffix:(NSString *)suffix
{
    NSString *content = self.string;
    NSUInteger location = range.location;
    NSUInteger length = range.length;
    if (content.length < location + length + suffix.length)
        return NO;
    if (location < prefix.length)
        return NO;

    if (![[content substringFromIndex:location + length] hasPrefix:suffix]
        || ![[content substringToIndex:location] hasSuffix:prefix])
        return NO;

    // Emphasis (*) requires special treatment because we need to eliminate
    // strong (**) but not strong-emphasis (***).
    if (![prefix isEqualToString:@"*"] || ![suffix isEqualToString:@"*"])
        return YES;
    if ([self substringInRange:range isSurroundedByPrefix:@"***" suffix:@"***"])
        return YES;
    if ([self substringInRange:range isSurroundedByPrefix:@"**" suffix:@"**"])
        return NO;
    return YES;
}


- (void)insertSpacesForTab
{
    NSString *spaces = @"    ";
    NSUInteger currentLocation = self.selectedRange.location;
    NSInteger p = [self.string locationOfFirstNewlineBefore:currentLocation];

    // Calculate how deep we need to go.
    NSUInteger offset = (currentLocation - p - 1) % 4;
    if (offset)
        spaces = [spaces substringFromIndex:offset];
    [self insertText:spaces];
}

- (BOOL)completeMatchingCharactersForTextInRange:(NSRange)range
                                      withString:(NSString *)str
                            strikethroughEnabled:(BOOL)strikethrough
{
    NSUInteger stringLength = str.length;

    // Character insert without selection.
    if (range.length == 0 && stringLength == 1)
    {
        NSUInteger location = range.location;
        if ([self completeMatchingCharacterForText:str
                                        atLocation:location])
            return YES;
    }
    // Character insert with selection (i.e. select and replace).
    else if (range.length > 0 && stringLength == 1)
    {
        unichar character = [str characterAtIndex:0];
        if ([self wrapMatchingCharactersOfCharacter:character
                                  aroundTextInRange:range
                               strikethroughEnabled:strikethrough])
            return YES;
    }
    return NO;
}

- (BOOL)completeMatchingCharacterForText:(NSString *)string
                              atLocation:(NSUInteger)location
{
    NSString *content = self.string;

    unichar c = [string characterAtIndex:0];
    unichar n = '\0';
    if (location < content.length)
        n = [content characterAtIndex:location];

    for (const unichar *cs = kMPMatchingCharactersMap[0]; *cs != 0; cs += 2)
    {
        if (c == cs[0] && n != cs[1])
        {
            NSRange range = NSMakeRange(location, 0);
            NSString *completion = [NSString stringWithCharacters:cs length:2];
            [self insertText:completion replacementRange:range];

            range.location += string.length;
            self.selectedRange = range;
            return YES;
        }
        else if (c == cs[1] && n == cs[1])
        {
            NSRange range = NSMakeRange(location + 1, 0);
            self.selectedRange = range;
            return YES;
        }
    }
    return NO;
}

- (void)wrapTextInRange:(NSRange)range withPrefix:(unichar)prefix
                 suffix:(unichar)suffix
{
    NSString *string = [self.string substringWithRange:range];
    NSString *p = [NSString stringWithCharacters:&prefix length:1];
    NSString *s = [NSString stringWithCharacters:&suffix length:1];
    NSString *wrapped = [NSString stringWithFormat:@"%@%@%@", p, string, s];
    [self insertText:wrapped replacementRange:range];

    range.location += 1;
    self.selectedRange = range;
}

- (BOOL)wrapMatchingCharactersOfCharacter:(unichar)character
                        aroundTextInRange:(NSRange)range
                     strikethroughEnabled:(BOOL)isStrikethroughEnabled
{
    for (const unichar *cs = kMPMatchingCharactersMap[0]; *cs != 0; cs += 2)
    {
        if (character == cs[0])
        {
            [self wrapTextInRange:range withPrefix:cs[0] suffix:cs[1]];
            return YES;
        }
    }
    for (size_t i = 0; kMPMarkupCharacters[i] != 0; i++)
    {
        if (character == kMPMarkupCharacters[i])
        {
            [self wrapTextInRange:range withPrefix:character suffix:character];
            return YES;
        }
    }
    if (isStrikethroughEnabled && character == kMPStrikethroughCharacter)
    {
        [self wrapTextInRange:range withPrefix:character suffix:character];
        return YES;
    }
    return NO;
}

- (BOOL)deleteMatchingCharactersAround:(NSUInteger)location
{
    NSString *string = self.string;
    if (location == 0 || location >= string.length)
        return NO;

    unichar f = [string characterAtIndex:location - 1];
    unichar b = [string characterAtIndex:location];

    for (const unichar *cs = kMPMatchingCharactersMap[0]; *cs != 0; cs += 2)
    {
        if (f == cs[0] && b == cs[1])
        {
            [self replaceCharactersInRange:NSMakeRange(location - 1, 2)
                                withString:@""];
            return YES;
        }
    }
    return NO;
}

- (BOOL)unindentForSpacesBefore:(NSUInteger)location
{
    NSString *string = self.string;

    NSUInteger whitespaceCount = 0;
    while (location - whitespaceCount > 0
           && [string characterAtIndex:location - whitespaceCount - 1] == L' ')
    {
        whitespaceCount++;
        if (whitespaceCount >= 4)
            break;
    }
    if (whitespaceCount < 2)
        return NO;

    NSUInteger offset =
        ([self.string locationOfFirstNewlineBefore:location] + 1) % 4;
    if (offset == 0)
        offset = 4;
    offset = offset > whitespaceCount ? whitespaceCount : 4;
    NSRange range = NSMakeRange(location - offset, offset);
    [self replaceCharactersInRange:range withString:@""];
    return YES;
}

- (void)toggleForMarkupPrefix:(NSString *)prefix suffix:(NSString *)suffix
{
    NSRange range = self.selectedRange;
    NSString *selection = [self.string substringWithRange:range];

    // Selection is already marked-up. Clear markup and maintain selection.
    NSUInteger poff = prefix.length;
    if ([self substringInRange:range isSurroundedByPrefix:prefix
                        suffix:suffix])
    {
        NSRange sub = NSMakeRange(range.location - poff,
                                  selection.length + poff + suffix.length);
        [self insertText:selection replacementRange:sub];
        range.location = sub.location;
    }
    // Selection is normal. Mark it up and maintain selection.
    else
    {
        NSString *text = [NSString stringWithFormat:@"%@%@%@",
                          prefix, selection, suffix];
        [self insertText:text replacementRange:range];
        range.location += poff;
    }
    self.selectedRange = range;
}

- (BOOL)insertMappedContent
{
    NSString *content = self.string;
    NSUInteger contentLength = content.length;
    if (contentLength > 20)
        return NO;
    static NSDictionary *map = nil;
    if (!map)
    {
        NSBundle *bundle = [NSBundle mainBundle];
        NSString *filePath = [bundle pathForResource:@"data" ofType:@"map"
                                         inDirectory:@"data"];
        map = [NSKeyedUnarchiver unarchiveObjectWithFile:filePath];
    }
    NSData *mapped = map[content];
    if (!mapped)
        return NO;
    NSArray *components = @[NSTemporaryDirectory(),
                             [NSString stringWithFormat:@"%lu", content.hash]];
    NSString *path = [NSString pathWithComponents:components];
    [mapped writeToFile:path atomically:NO];
    NSString *text = [NSString stringWithFormat:@"![%@](%@)", content, path];
    [self insertText:text replacementRange:NSMakeRange(0, contentLength)];
    self.selectedRange = NSMakeRange(2, contentLength);
    return YES;
}

- (BOOL)completeNextLine
{
    NSRange selectedRange = self.selectedRange;
    NSUInteger location = selectedRange.location;
    NSString *content = self.string;
    if (selectedRange.length || !content.length)
        return NO;

    NSInteger start = [content locationOfFirstNewlineBefore:location] + 1;
    NSUInteger end = location;
    NSUInteger nonwhitespace =
        [content locationOfFirstNonWhitespaceCharacterInLineBefore:location];

    // No non-whitespace character at this line.
    if (nonwhitespace == location)
        return NO;

    NSRange range = NSMakeRange(start, end - start);
    NSString *line = [self.string substringWithRange:range];

    static NSString * const pattern =
        @"^(\\s*)((?:(?:\\*|\\+|-|)\\s)?)((?:\\d+\\.\\s)?)(\\S)?";

    NSRegularExpressionOptions options = NSRegularExpressionAnchorsMatchLines;
    NSRegularExpression *regex =
        [[NSRegularExpression alloc] initWithPattern:pattern options:options
                                               error:NULL];
    NSTextCheckingResult *result =
        [regex firstMatchInString:line options:0
                            range:NSMakeRange(0, line.length)];
    if (!result || result.range.location == NSNotFound)
        return NO;

    NSMutableString *indent = [[NSMutableString alloc] init];
    for (NSUInteger i = 0; i < [result rangeAtIndex:1].length; i++)
        [indent appendString:@" "];

    NSString *t = nil;
    BOOL isUl = ([result rangeAtIndex:2].length != 0);
    BOOL isOl = ([result rangeAtIndex:3].length != 0);
    BOOL previousLineEmpty = ([result rangeAtIndex:4].length == 0);
    if (previousLineEmpty)
    {
        NSRange replaceRange = NSMakeRange(NSNotFound, 0);
        if (isUl)
            replaceRange = [result rangeAtIndex:2];
        else if (isOl)
            replaceRange = [result rangeAtIndex:3];
        if (replaceRange.length)
        {
            replaceRange.location += start;
            [self replaceCharactersInRange:range withString:@""];
        }
    }
    else if (isUl)
    {
        t = [line substringWithRange:[result rangeAtIndex:2]];
    }
    else if (isOl)
    {
        NSRange range = [result rangeAtIndex:3];
        range.length -= 1;      // Exclude trailing space.
        NSString *captured = [line substringWithRange:range];
        NSInteger i = captured.integerValue + 1;
        t = [NSString stringWithFormat:@"%ld. ", i];
    }
    [self insertNewline:self];
    if (t)
        [self insertText:[NSString stringWithFormat:@"%@%@", indent, t]];
    return YES;
}

@end
