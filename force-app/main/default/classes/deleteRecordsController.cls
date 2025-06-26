public with sharing class deleteRecordsController {
    @AuraEnabled
    public static String deleteImportDealerData(String importRecordId) {
        if (String.isBlank(importRecordId)) {
            throw new AuraHandledException('Import Record Id is required.');
        }

        // Check RecordType
        RecordType expectedRT = [
            SELECT Id 
            FROM RecordType 
            WHERE SObjectType = 'Import__c' 
            AND DeveloperName = 'Sales_Monthly_Summaries' 
            LIMIT 1
        ];

        Import__c importRecord = [
            SELECT RecordTypeId 
            FROM Import__c 
            WHERE Id = :importRecordId 
            LIMIT 1
        ];

        if (importRecord.RecordTypeId != expectedRT.Id) {
            throw new AuraHandledException('Only Sales Monthly Summaries records can be processed.');
        }
        return Database.executeBatch(new deleteDealerImportDataBatch(importRecordId), 500);
    }
}