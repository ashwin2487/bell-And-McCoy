public with sharing class DealerImportBatchService {
    @AuraEnabled
    public static void runBatch(Id importRecordId) {
        if (importRecordId == null) {
            throw new AuraHandledException('Import record ID is required.');
        }
        Integer batchSize;
        batchSize = Integer.valueOf(Label.dealerImportbatchSize);
        
        
        DealerImportBatchV1 batchJob = new DealerImportBatchV1(importRecordId, batchSize);
        Database.executeBatch(batchJob, batchSize);
    }
    
}