public class CommissionImportBatchService {
    @AuraEnabled
    public static void runBatch(Id importRecordId) {
        if (importRecordId == null) {
            throw new AuraHandledException('Import record ID is required.');
        }
        Integer batchSize;
        batchSize = Integer.valueOf(Label.dealerImportbatchSize);
                
        CommissionImportBatchV1 batchJob = new CommissionImportBatchV1(importRecordId, batchSize);
        Database.executeBatch(batchJob, batchSize);
    }
    
}