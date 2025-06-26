public class rollBackAssociatedRecordsController {
    @AuraEnabled
    public static String rollBackAssociatedRecords(String importRecordId) {
        try {
            if (String.isBlank(importRecordId)) {
                throw new AuraHandledException('Import Record Id is required.');
            }

            // Get expected Record Type for 'Sales_Monthly_Summaries'
            RecordType expectedRT = [
                SELECT Id 
                FROM RecordType 
                WHERE SObjectType = 'Import__c' 
                AND DeveloperName = 'Sales_Monthly_Summaries' 
                LIMIT 1
            ];

            // Fetch the import record
            Import__c importRecord = [
                SELECT RecordTypeId 
                FROM Import__c 
                WHERE Id = :importRecordId 
                LIMIT 1
            ];

            // Validate Record Type
            if (importRecord.RecordTypeId != expectedRT.Id) {
                throw new AuraHandledException('Only Sales Monthly Summaries records can be processed.');
            }

            // Launch batch if valid
            String jobId = Database.executeBatch(new rollbackAssociatedRecordsBatch(importRecordId), 200);
            return jobId;

        } catch (Exception e) {
            System.debug('Error in rollBackAssociatedRecords: ' + e.getMessage() + ' | Line: ' + e.getLineNumber());
            throw new AuraHandledException('Error: ' + e.getMessage());
        }
    }
}