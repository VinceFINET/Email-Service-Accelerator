public with sharing class Case_ThreadIdGenerator {
  
    private static String shortenId(String idValue) {
        String[] keys = idValue.left(15).split('');
        while(keys.size() > 5 && keys[5] == '0') {
            keys.remove(5);
        }
        return String.join(keys,'');
    }

    public static List<String> extractThreadIds(String text) {
        String[] parts = text.split('ref');
        String start = ':_' + shortenId(UserInfo.getOrganizationId()) + '._';
        List<String> threadids = new List<String>();
        for (String t : parts) {
            if (t.startsWith(start) && t.endsWith(':')) {
                threadids.add('ref'+t+'ref');
            }
        }
        return threadids;
    }

    public static String getThreadId(Id caseId) {
        return 
            'ref:_' + shortenId(UserInfo.getOrganizationId()) +
            '._'    + shortenId(caseId) +  ':ref';
    }
}