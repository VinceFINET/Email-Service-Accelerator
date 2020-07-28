global with sharing class EmailService_Handler implements Messaging.InboundEmailHandler {
    
    global Messaging.InboundEmailResult handleInboundEmail(Messaging.InboundEmail email, Messaging.InboundEnvelope envelope) {
        
        Messaging.InboundEmailResult result = new Messaging.InboundEmailresult();
        
        // 1. Finding the corresponding Contact from sender (can be null)
        Contact sender = searchContactFromEmailAddress(email.fromAddress);
        
        // 2. Getting the thread id from the email (if any)
        String threadId = getThreadIdFromEmail(email);
        
        // 3. Search or create the case in SF
        Case mycase = searchCaseFromThreadId(threadId, email, sender);
        
        // 4. Extract, filter and insert attachment in SF
        Map<String, ContentVersion> attachments = insertAttachments(email);
        
        // 5. Creation of the Email MEssage associated with the case
        EmailMessage emailMessage = createEmailMessage(email, attachments, mycase, threadId);
        
        // 6. Associate the images to the email message
        createDocumentLinks(attachments.values(), emailMessage);
        
        return result;
    }
    
    private static Contact searchContactFromEmailAddress(String emailAddress) {
        // 1. We look for a contact with the "from" email address
        List<Contact> contacts = [SELECT Id, AccountId 
                                  FROM Contact 
                                  WHERE Email = :emailAddress];
        // 2. We take the first one in the list if it is not empty
        if (contacts.size() > 0) return contacts[0];
        // 3. Return null otherwise
        return null;
    }
    
    private static String getThreadIdFromEmail(Messaging.InboundEmail email) {
        // 1. All the data where we will search for thread ids
        List<String> data = new List<String> { email.subject, email.plainTextBody, email.htmlBody };
        // 2. Loop, BUT as soon as we found we stop the loop
        for (String d : data) {
            // 3. Get the thread id (already filtered with the current orgid)
          List<String> ts = Case_ThreadIdGenerator.extractThreadIds(d);
            if (ts.isEmpty() == false) {
                // 4. return the first one if multiple
                return ts.get(0);
            }
        }
        // 5. Return null otherwise
        return null;
    }

    private static Case searchCaseFromThreadId(String threadId, Messaging.InboundEmail email, Contact sender) {
        // 1. If the given Thread Id is specified
        if (threadId != null) {
            // 2. Look for the thread id (note that this custom field is indexed)
            List<Case> cases = [SELECT Id 
                                FROM Case 
                                WHERE ThreadId__c = :threadId];
            // 3. If found, we take the first one in the list
            if (cases.isEmpty() == false) {
                return cases[0];
            }
        }
        // 4. If not found, we will create a new case for this
        Case newcase = new Case(
            Status='New', Origin='Email', 
            Subject=email.subject, Description=email.plainTextBody, 
            SuppliedEmail=email.fromAddress, SuppliedName=email.fromName
        );
        if (sender != null) {
            newcase.ContactId = sender.Id;
            newcase.AccountId = sender.AccountId;
        }
        insert newcase;
        return newcase;
    }
    
    private static Map<String, ContentVersion> insertAttachments(Messaging.InboundEmail email) {
        Map<String, ContentVersion> allAttachments = new Map<String, ContentVersion>();
        Map<String, ContentVersion> newAttachments = new Map<String, ContentVersion>();
        Integer count = 0;
        if (email.binaryAttachments != null) {
            for (Messaging.InboundEmail.BinaryAttachment att : email.binaryAttachments) {
                if (att.filename != null && att.filename.endsWith('.eml')) continue;
                if (att.mimeTypeSubType != null && att.mimeTypeSubType.equalsIgnoreCase('message/rfc822')) continue;       
                String cid = 'binary-content-id-' + count++;
                if (att.headers != null) {
                    for (Messaging.InboundEmail.Header header : att.headers) if (header.name == 'Content-ID') {
                        cid = header.value;
                        if (cid != null) cid = cid.replace('<', '').replace('>', '');
                        break;
                    }
                }
                String checksum = ContentVersion_ChecksumGenerator.calculateChecksum(att.body);
                // Insert only if it is a good checksum
                if (ContentVersion_ChecksumGenerator.isBadChecksum(checksum) == false) {
                    // Is the file existing already?
                    List<ContentVersion> existing = [SELECT Id FROM ContentVersion WHERE Checksum__c = :checksum ];
                    if (existing.isEmpty() == false) {
                        allAttachments.put(cid, existing[0]);
                    } else {
                        // New file
                        newAttachments.put(cid, new ContentVersion(
                            Title = att.filename,
                            VersionData = att.body,
                            PathOnClient = att.filename 
                        ));
                    }
                }
            }
        }
        if (email.textAttachments != null) {
            for (Messaging.InboundEmail.TextAttachment att : email.textAttachments) {
                if (att.filename != null && att.filename.endsWith('.eml')) continue;
                String cid = 'text-content-id-' + count++;
                Blob body = Blob.valueof(att.body);
                String checksum = ContentVersion_ChecksumGenerator.calculateChecksum(body);
                // Insert only if it is a good checksum
                if (ContentVersion_ChecksumGenerator.isBadChecksum(checksum) == false) {
                    // Is the file existing already?
                    List<ContentVersion> existing = [SELECT Id FROM ContentVersion WHERE Checksum__c = :checksum ];
                    if (existing.isEmpty() == false) {
                        allAttachments.put(cid, existing[0]);
                    } else {
                        // New file
                        newAttachments.put(cid, new ContentVersion(
                            Title = att.filename,
                            VersionData = body,
                            PathOnClient = att.filename 
                        ));
                    }
                }
            }
        }
        insert newAttachments.values();
        allAttachments.putAll(newAttachments);
        return allAttachments;
    }

    private static void createDocumentLinks(List<ContentVersion> attachments, EmailMessage emailMessage) {
        // 1. Get the Version Ids in a set (for SOQL)
        Set<Id> versionIds = new Set<Id>();
        for (ContentVersion att : attachments) {
            versionIds.add(att.Id);
        }
        // 2. Get the Document Ids from the Version Ids
        Set<Id> documentIds = new Set<Id>();
        for (ContentVersion att : [SELECT Id, ContentDocumentId 
                                   FROM ContentVersion
                                   WHERE Id IN :versionIds]) {
            documentIds.add(att.ContentDocumentId);
        }
        // 3. Insert the document link now!!
        List<ContentDocumentLink> links = new List<ContentDocumentLink>();
        for (Id docId : documentIds) {
            links.add(new ContentDocumentLink(
                ShareType = 'V',
                LinkedEntityId = emailMessage.Id,
                ContentDocumentId = docId,
                Visibility = 'AllUsers'
            ));
        }
        insert links;
    }

    private static EmailMessage createEmailMessage(Messaging.InboundEmail email, Map<String, ContentVersion> attachments, Case mycase, String threadId) {
        // 1. Generate the headers as string
        String headersAsString = '';
        for (Messaging.InboundEmail.Header header : email.headers) {
            headersAsString += header.name + ': ' + header.value + '\n';
        }
        // 2. Generate the addresses as string
        String toAddressesAsString = '';
        for (String toAddress : email.toAddresses) {
            toAddressesAsString += toAddress + '; ';
        }
        // 3. Update the inline urls 
        String textBody = email.plainTextBody;
        String htmlBody = email.htmlBody;
        for (String cid : attachments.keySet()) {
            // WARNING: puting the inline images in the email will include it AGAIN when the agent replies to it!
            String url = '/sfc/servlet.shepherd/version/download/'+attachments.get(cid).Id;
            textBody = textBody.replaceAll('cid:' + cid, url);
            htmlBody = htmlBody.replaceAll('cid:' + cid, url);
        }
        // 4. Create the Email Message in database
        EmailMessage emailMessage = new EmailMessage(
            Incoming = true,
            ParentId = mycase.Id,
            TextBody = textBody, 
            HtmlBody = htmlBody, 
            Headers = headersAsString, 
            Subject = email.subject, 
            FromName = email.fromName, 
            FromAddress = email.fromAddress, 
            ToAddress = toAddressesAsString, 
            Status = '0', // New 
            MessageDate = Datetime.now(),
            MessageIdentifier = email.messageId, 
            IsClientManaged = true, // need this for attachments
            ThreadIdentifier = threadId
        );
        insert emailMessage;
        return emailMessage;
    }
}