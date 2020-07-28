trigger CaseTrigger on Case (after insert) {

    List<Case> cases = new List<Case>();
    for (Case record : Trigger.new) {
        cases.add(new Case(
            Id = record.Id, 
            ThreadId__c = Case_ThreadIdGenerator.getThreadId(record.Id)
        ));
    }
    if (cases.isEmpty() == false) update cases;
    
}