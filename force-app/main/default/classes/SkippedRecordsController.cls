public with sharing class SkippedRecordsController {
    public class SkippedRecordsResponse {
        @AuraEnabled public String batchJobId;
        @AuraEnabled public String message;
        
        public SkippedRecordsResponse(String batchJobId, String message) {
            this.batchJobId = batchJobId;
            this.message = message;
        }
    }
    @AuraEnabled
    public static SkippedRecordsResponse processRecordsSkipped(String importRecordId) {
        if (String.isNotBlank(importRecordId)) {
            try {
                import__c record = [
                    SELECT Id, Name, RecordType.DeveloperName
                    FROM import__c
                    WHERE Id = :importRecordId
                    LIMIT 1
                ];
                if (record.RecordType.DeveloperName != 'Sales_Monthly_Summaries') {
                    return new SkippedRecordsResponse(null, 'Only Sales Monthly Summaries records can be processed.');
                }
                SkippedRecordsBatch batchJob = new SkippedRecordsBatch(importRecordId);
                String batchJobId = Database.executeBatch(batchJob, 500);
                return new SkippedRecordsResponse(batchJobId, 'Batch job started successfully.');
                
            } catch (Exception e) {
                return new SkippedRecordsResponse(null, 'Error: ' + e.getMessage());
            }
        } else {
            throw new AuraHandledException('Import Record Id is required.');
        }
    }
    
}