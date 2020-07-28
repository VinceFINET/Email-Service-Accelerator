trigger ContentVersionTrigger on ContentVersion (before insert) {

    for (ContentVersion record : Trigger.new) {
        record.Checksum__c = ContentVersion_ChecksumGenerator.calculateChecksum(record.VersionData);
    }

}