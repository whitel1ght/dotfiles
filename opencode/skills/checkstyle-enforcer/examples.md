# Checkstyle Violation Examples

This file provides detailed examples of common checkstyle violations and their fixes.

## LineLength Violations

### Example 1: Long Method Signature

**Before (165 characters)**:
```java
public HttpResponse<EmailInboxItem> processInboundWebhookWithAuthentication(PostmarkInboundRequest request, String apiKey, Long firmId) {
```

**After (proper line wrapping)**:
```java
public HttpResponse<EmailInboxItem> processInboundWebhookWithAuthentication(
        PostmarkInboundRequest request, String apiKey, Long firmId) {
```

### Example 2: Long Method Call Chain

**Before (180 characters)**:
```java
EmailInboxItem item = repository.findByFirmId(firmId).stream().filter(i -> i.getStatus() == Status.PENDING).findFirst().orElseThrow(() -> new NotFoundException());
```

**After (proper line wrapping)**:
```java
EmailInboxItem item = repository.findByFirmId(firmId)
        .stream()
        .filter(i -> i.getStatus() == Status.PENDING)
        .findFirst()
        .orElseThrow(() -> new NotFoundException());
```

### Example 3: Long String Literal

**Before (160 characters)**:
```java
String errorMessage = "The email processing failed due to invalid firm configuration. Please verify the firm settings and retry the operation.";
```

**After (string concatenation)**:
```java
String errorMessage = "The email processing failed due to invalid firm configuration. "
        + "Please verify the firm settings and retry the operation.";
```

### Example 4: Multiple Method Parameters

**Before (155 characters)**:
```java
service.createInboxItem(firm, rawEmail, sender, subject, body, attachments, receivedAt, processedAt);
```

**After (grouped logically)**:
```java
service.createInboxItem(
        firm, rawEmail, sender, subject,
        body, attachments, receivedAt, processedAt);
```

## CustomImportOrder Violations

### Example: Unsorted Imports

**Before (incorrect order)**:
```java
package com.goecfx.controllers;

import java.util.List;
import io.micronaut.http.HttpResponse;
import static org.junit.jupiter.api.Assertions.assertEquals;
import com.goecfx.services.EmailProcessingService;
import jakarta.inject.Singleton;
import java.time.Instant;
import io.micronaut.security.annotation.Secured;
```

**After (correct grouping and sorting)**:
```java
package com.goecfx.controllers;

import static org.junit.jupiter.api.Assertions.assertEquals;

import com.goecfx.services.EmailProcessingService;
import io.micronaut.http.HttpResponse;
import io.micronaut.security.annotation.Secured;
import jakarta.inject.Singleton;

import java.time.Instant;
import java.util.List;
```

**Grouping Rules**:
1. Static imports (alphabetical)
2. Blank line
3. Third-party packages: com, io, org, jakarta (alphabetical)
4. Blank line
5. Standard Java packages: java, javax (alphabetical)

## WhitespaceAfter Violations

### Example: Missing Spaces After Commas

**Before**:
```java
List<String> items = Arrays.asList("item1","item2","item3");
method(param1,param2,param3);
for (int i = 0;i < 10;i++) {
```

**After**:
```java
List<String> items = Arrays.asList("item1", "item2", "item3");
method(param1, param2, param3);
for (int i = 0; i < 10; i++) {
```

### Example: Missing Space After Control Flow Keywords

**Before**:
```java
if(condition) {
while(running) {
for(Item item : items) {
```

**After**:
```java
if (condition) {
while (running) {
for (Item item : items) {
```

## WhitespaceAround Violations

### Example: Missing Spaces Around Operators

**Before**:
```java
int result=a+b*c-d/e;
String name=firstName+" "+lastName;
boolean valid=count>0&&status==Status.ACTIVE;
```

**After**:
```java
int result = a + b * c - d / e;
String name = firstName + " " + lastName;
boolean valid = count > 0 && status == Status.ACTIVE;
```

### Example: Missing Spaces Around Braces

**Before**:
```java
if (condition){doSomething();}
void method(){
    // implementation
}
```

**After**:
```java
if (condition) { doSomething(); }
void method() {
    // implementation
}
```

## JavadocParagraph Violations

### Example: Incorrect Paragraph Tag Formatting

**Before**:
```java
/**
 * Processes an inbound email webhook.
 * <p> This method creates an inbox item and a processing job.
 * <p>Additional processing may be performed asynchronously.
 */
```

**After**:
```java
/**
 * Processes an inbound email webhook.
 *
 * <p>This method creates an inbox item and a processing job.
 *
 * <p>Additional processing may be performed asynchronously.
 */
```

**Rules**:
- Empty line (just `*`) before `<p>` tag
- No space after `<p>` tag

## MissingJavadocMethod Violations

### Example: Public Method Without Javadoc

**Before**:
```java
@Transactional
public EmailInboxItem processInboundEmail(PostmarkInboundRequest request) {
    Firm firm = resolveFirm(request);
    EmailInboxItem item = createInboxItem(firm, request);
    return repository.save(item);
}
```

**After**:
```java
/**
 * Processes an inbound email from Postmark webhook.
 *
 * <p>Creates an email inbox item and saves it to the database.
 * The firm is resolved based on the recipient address.
 *
 * @param request the Postmark inbound webhook request containing email data
 * @return the created and persisted email inbox item
 */
@Transactional
public EmailInboxItem processInboundEmail(PostmarkInboundRequest request) {
    Firm firm = resolveFirm(request);
    EmailInboxItem item = createInboxItem(firm, request);
    return repository.save(item);
}
```

### Example: Method with Multiple Parameters and Exceptions

**Before**:
```java
public void validateAndProcess(String email, Long firmId, boolean sendNotification)
        throws ValidationException, ProcessingException {
    // implementation
}
```

**After**:
```java
/**
 * Validates email data and processes it for the specified firm.
 *
 * @param email the email address to validate
 * @param firmId the ID of the firm to process the email for
 * @param sendNotification whether to send a notification after processing
 * @throws ValidationException if the email fails validation
 * @throws ProcessingException if processing fails
 */
public void validateAndProcess(String email, Long firmId, boolean sendNotification)
        throws ValidationException, ProcessingException {
    // implementation
}
```

## MissingJavadocType Violations

### Example: Controller Without Javadoc

**Before**:
```java
@Controller("/webhooks/postmark")
@Secured(SecurityRule.IS_AUTHENTICATED)
public class PostmarkController {
    private final EmailProcessingService service;
    // methods...
}
```

**After**:
```java
/**
 * Controller for handling Postmark inbound email webhooks.
 *
 * <p>Receives webhook requests from Postmark, authenticates them,
 * and delegates processing to the email processing service.
 */
@Controller("/webhooks/postmark")
@Secured(SecurityRule.IS_AUTHENTICATED)
public class PostmarkController {
    private final EmailProcessingService service;
    // methods...
}
```

### Example: Service Class Without Javadoc

**Before**:
```java
@Singleton
public class EmailProcessingService {
    private final EmailInboxItemRepository repository;
    private final FirmRepository firmRepository;
    // methods...
}
```

**After**:
```java
/**
 * Service for processing inbound email webhooks.
 *
 * <p>Handles email ingestion from Postmark and Sendgrid webhooks,
 * creating inbox items and processing jobs for asynchronous handling.
 */
@Singleton
public class EmailProcessingService {
    private final EmailInboxItemRepository repository;
    private final FirmRepository firmRepository;
    // methods...
}
```

## EmptyLineSeparator Violations

### Example: Missing Blank Lines

**Before**:
```java
package com.goecfx.services;
import io.micronaut.http.HttpResponse;
import jakarta.inject.Singleton;
@Singleton
public class MyService {
    private final Repository repository;
    public MyService(Repository repository) {
        this.repository = repository;
    }
    public void doSomething() {
        // implementation
    }
}
```

**After**:
```java
package com.goecfx.services;

import io.micronaut.http.HttpResponse;
import jakarta.inject.Singleton;

@Singleton
public class MyService {
    private final Repository repository;

    public MyService(Repository repository) {
        this.repository = repository;
    }

    public void doSomething() {
        // implementation
    }
}
```

## OperatorWrap Violations

### Example: Incorrect Operator Line Breaks

**Before** (operator at end of line):
```java
String message = "This is a long string that needs " +
        "to be broken across multiple lines " +
        "for readability.";

boolean condition = value1 > 10 &&
        value2 < 20 ||
        value3 == 30;
```

**After** (operator at beginning of new line):
```java
String message = "This is a long string that needs "
        + "to be broken across multiple lines "
        + "for readability.";

boolean condition = value1 > 10
        && value2 < 20
        || value3 == 30;
```

## SeparatorWrap Violations

### Example: Incorrect Comma/Dot Line Breaks

**Before** (comma at beginning of new line):
```java
method(param1
    , param2
    , param3);

object
    .method1()
    .method2();
```

**After** (comma at end of line, dot at beginning):
```java
method(param1,
    param2,
    param3);

object
        .method1()
        .method2();
```

**Rules**:
- Comma (`,`): End of line (EOL)
- Dot (`.`): New line (NL) - at beginning of continuation line
- Method reference (`::`): New line (NL)

## Indentation Violations

### Example: Incorrect Indentation

**Before**:
```java
public void method() {
if (condition) {
doSomething();
} else {
    doSomethingElse();
}
}
```

**After**:
```java
public void method() {
    if (condition) {
        doSomething();
    } else {
        doSomethingElse();
    }
}
```

### Example: Continuation Line Indentation

**Before** (4 spaces instead of 8):
```java
String result = someVeryLongMethodName(
    parameter1, parameter2);
```

**After** (8 spaces for continuation):
```java
String result = someVeryLongMethodName(
        parameter1, parameter2);
```

## AbbreviationAsWordInName Violations (Manual Fix)

### Example: Too Many Consecutive Capitals

**Before** (5+ consecutive capitals)**:
```java
public class HTMLURLParser {
    private String parseHTMLURL(String input) {
        String HTMLCONTENT = extractHTML(input);
        return processHTMLURL(HTMLCONTENT);
    }
}
```

**After** (max 4 consecutive capitals):
```java
public class HtmlUrlParser {
    private String parseHtmlUrl(String input) {
        String htmlContent = extractHtml(input);
        return processHtmlUrl(htmlContent);
    }
}
```

**Allowed** (4 or fewer consecutive capitals):
- `URL` (3 capitals)
- `HTML` (4 capitals)
- `HTTP` (4 capitals)
- `JSON` (4 capitals)
- `XMLParser` (3 capitals followed by normal case)

**Not Allowed** (5+ consecutive capitals):
- `HTMLURL` (7 capitals) → Use `HtmlUrl`
- `HTTPSConnection` (5 capitals) → Use `HttpsConnection`
- `JSONAPIResponse` (7 capitals) → Use `JsonApiResponse`

## Complex Example: Multiple Violations in One File

**Before**:
```java
package com.goecfx.controllers;
import java.util.List;
import io.micronaut.http.HttpResponse;
import jakarta.inject.Singleton;
@Singleton
public class PostmarkController {
    private final EmailProcessingService service;
    public PostmarkController(EmailProcessingService service) {this.service=service;}
    public HttpResponse<Void> handleInbound(PostmarkInboundRequest request,String apiKey,Long firmId) throws ProcessingException {
        if(request==null){throw new IllegalArgumentException("Request cannot be null");}
        service.processInboundEmail(request,apiKey,firmId);
        return HttpResponse.ok();
    }
}
```

**After** (all violations fixed):
```java
package com.goecfx.controllers;

import io.micronaut.http.HttpResponse;
import jakarta.inject.Singleton;

import java.util.List;

/**
 * Controller for handling Postmark inbound email webhooks.
 *
 * <p>Receives webhook requests from Postmark and delegates processing
 * to the email processing service.
 */
@Singleton
public class PostmarkController {
    private final EmailProcessingService service;

    /**
     * Constructs a new PostmarkController.
     *
     * @param service the email processing service
     */
    public PostmarkController(EmailProcessingService service) {
        this.service = service;
    }

    /**
     * Handles an inbound email webhook from Postmark.
     *
     * @param request the inbound email request
     * @param apiKey the API key for authentication
     * @param firmId the ID of the firm receiving the email
     * @return HTTP 200 OK response
     * @throws ProcessingException if email processing fails
     */
    public HttpResponse<Void> handleInbound(
            PostmarkInboundRequest request, String apiKey, Long firmId)
            throws ProcessingException {
        if (request == null) {
            throw new IllegalArgumentException("Request cannot be null");
        }
        service.processInboundEmail(request, apiKey, firmId);
        return HttpResponse.ok();
    }
}
```

**Violations Fixed**:
1. CustomImportOrder - sorted and grouped imports
2. EmptyLineSeparator - added blank lines between sections
3. MissingJavadocType - added class Javadoc
4. MissingJavadocMethod - added constructor and method Javadoc
5. WhitespaceAround - added spaces around `=`, `==`, `{`, `}`
6. WhitespaceAfter - added spaces after commas
7. LineLength - broke long method signature
8. LeftCurly - proper brace placement
