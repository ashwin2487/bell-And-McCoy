public class UpdateMoMReportController {
    @AuraEnabled
    public static String runBatch(Id momReportId) {
        if (momReportId == null) {
            throw new AuraHandledException('Error: MoM record ID is required.');
        }
        
        try {
            // Validate the MoM Report record
            mom_report__c momRecord = validateMoMRecord(momReportId);
            
            // Get batch size from custom label with fallback
            Integer batchSize = getBatchSize();
            
            // Execute the batch
            Id jobId = Database.executeBatch(new UpdateMoMReportProcess(momReportId, batchSize), batchSize);
            
            return 'Batch job started successfully. Job ID: ' + jobId;
            
        } catch (QueryException e) {
            throw new AuraHandledException('Error: MoM Report record not found or access denied.');
        } catch (Exception e) {
            System.debug('Unexpected error in runBatch: ' + e.getMessage());
            throw new AuraHandledException('An unexpected error occurred: ' + e.getMessage());
        }
    }
    
    private static mom_report__c validateMoMRecord(Id momReportId) {
        List<mom_report__c> momRecords = [
            SELECT Id, invoice_date_end__c, invoice_date_start__c, Import__c, 
            Import__r.RecordTypeId, mom_report_date__c, Vendor__c
            FROM mom_report__c 
            WHERE Id = :momReportId
            LIMIT 1
        ];
        
        if (momRecords.isEmpty()) {
            throw new AuraHandledException('Error: MoM Report record not found.');
        }
        
        mom_report__c momRecord = momRecords[0];
        
        // Validate Import Record Type
        validateImportRecordType(momRecord);
        
        // Validate required fields
        validateRequiredFields(momRecord);
        
        // Validate date range
        validateDateRange(momRecord);
        
        return momRecord;
    }
    
    private static void validateImportRecordType(mom_report__c momRecord) {
        List<RecordType> expectedRecordTypes = [
            SELECT Id 
            FROM RecordType 
            WHERE SObjectType = 'Import__c' AND DeveloperName = 'MoM_Commissions' 
            LIMIT 1
        ];
        
        if (expectedRecordTypes.isEmpty()) {
            throw new AuraHandledException('Error: MoM_Commissions record type not found.');
        }
        
        Id expectedRecordTypeId = expectedRecordTypes[0].Id;
        
        if (momRecord.Import__c == null) {
            throw new AuraHandledException('Error: Import record is missing.');
        }
        
        if (momRecord.Import__r.RecordTypeId != expectedRecordTypeId) {
            throw new AuraHandledException('Error: Only MoM Commission Reports can be processed.');
        }
    }
    
    private static void validateRequiredFields(mom_report__c momRecord) {
        if (momRecord.Vendor__c == null) {
            throw new AuraHandledException('Error: Vendor is required.');
        }
    }
    
    private static void validateDateRange(mom_report__c momRecord) {
        if (momRecord.invoice_date_start__c == null) {
            throw new AuraHandledException('Error: Invoice Start Date is required.');
        }
        
        if (momRecord.invoice_date_end__c == null) {
            throw new AuraHandledException('Error: Invoice End Date is required.');
        }
        
        if (momRecord.invoice_date_end__c <= momRecord.invoice_date_start__c) {
            throw new AuraHandledException('Error: End Date must be after the Start Date.');
        }
        
        // Optional: Add validation for reasonable date ranges
        if (momRecord.invoice_date_start__c.daysBetween(momRecord.invoice_date_end__c) > 365) {
            throw new AuraHandledException('Error: Date range cannot exceed 365 days.');
        }
    }
    
    private static Integer getBatchSize() {
        Integer batchSize = 200; // Default value
        
        try {
            String batchSizeLabel = Label.dealerImportbatchSize;
            if (String.isNotBlank(batchSizeLabel)) {
                batchSize = Integer.valueOf(batchSizeLabel);
                
                // Validate batch size is within reasonable bounds
                if (batchSize < 1 || batchSize > 2000) {
                    System.debug('Invalid batch size in label: ' + batchSize + '. Using default: 200');
                    batchSize = 200;
                }
            }
        } catch (Exception e) {
            System.debug('Error reading batch size from label: ' + e.getMessage() + '. Using default: 200');
            batchSize = 200;
        }
        
        return batchSize;
    }
    
}