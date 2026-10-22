public with sharing class PCRSectorDefinitions {
    private static Map<String, PCR_Sector_Definition__mdt> byDevName;
    private static Map<String, List<PCR_Sector_Definition__mdt>> byRound;

    private static void load() {
        if (byDevName != null) return;
        byDevName = new Map<String, PCR_Sector_Definition__mdt>();
        byRound = new Map<String, List<PCR_Sector_Definition__mdt>>();
        for (PCR_Sector_Definition__mdt d : [
            SELECT DeveloperName, Sector__c, Round__c, Approver_Group__c, Owned_Fields__c
            FROM PCR_Sector_Definition__mdt
        ]) {
            byDevName.put(d.DeveloperName, d);
            if (!byRound.containsKey(d.Round__c)) byRound.put(d.Round__c, new List<PCR_Sector_Definition__mdt>());
            byRound.get(d.Round__c).add(d);
        }
    }

    public static List<PCR_Sector_Definition__mdt> forRound(String round) {
        load();
        return byRound.containsKey(round) ? byRound.get(round) : new List<PCR_Sector_Definition__mdt>();
    }

    public static List<String> ownedFields(String developerName) {
        load();
        List<String> out = new List<String>();
        PCR_Sector_Definition__mdt d = byDevName.get(developerName);
        if (d != null && String.isNotBlank(d.Owned_Fields__c)) {
            for (String f : d.Owned_Fields__c.split(',')) {
                if (String.isNotBlank(f)) out.add(f.trim());
            }
        }
        return out;
    }
}