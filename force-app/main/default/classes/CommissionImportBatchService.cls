public with sharing class CommissionImportBatchService {
    @AuraEnabled
    public static void runBatch(Id importRecordId) {
        if (importRecordId == null) {
            throw new AuraHandledException('Error: Import record ID is required.');
        }

        Import__c importRecord = [SELECT Id, Vendor__c, Date_range_start__c, Date_range_end__c, RecordTypeId FROM Import__c WHERE Id = :importRecordId LIMIT 1];

        Id expectedRecordTypeId = [SELECT Id FROM RecordType WHERE SObjectType = 'Import__c' AND DeveloperName = 'MoM_Commissions'  LIMIT 1].Id;

        if (importRecord.RecordTypeId != expectedRecordTypeId) {
            throw new AuraHandledException('Only MoM Commission Reports can be processed.');
        }

        if (importRecord.Vendor__c == null) {
            throw new AuraHandledException('Error: Vendor is missing.');
        }

        if (importRecord.Date_range_start__c == null || 
            importRecord.Date_range_end__c == null || 
            importRecord.Date_range_end__c <= importRecord.Date_range_start__c) {
            throw new AuraHandledException('Error: End Date must be after the Start Date.');
        }

        Integer batchSize;
        try {
            batchSize = Integer.valueOf(Label.dealerImportbatchSize);
        } catch (Exception e) {
            batchSize = 200; 
        }

        Database.executeBatch(new CommissionImportBatchV1(importRecordId, batchSize), batchSize);
    }
}