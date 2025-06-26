global class CommissionImportBatchV1 implements Database.Batchable<Import_MoM_Commission_Data__c>, Database.Stateful {
    @TestVisible private Id importRecordId;
    @TestVisible private Integer batchSize;
    @TestVisible private Id strVendorId;
    @TestVisible private Date startDate;
    @TestVisible private Date endDate;
    @TestVisible private Id momReportId;
    @TestVisible private String errorMessage;
    @TestVisible private Integer totalProcessed = 0;
    @TestVisible private Integer totalSkipped = 0;
    @TestVisible private Integer totalErrors = 0;

    public CommissionImportBatchV1(Id importRecordId, Integer batchSize) {
        this.importRecordId = importRecordId;
        this.batchSize = batchSize;
    }

    global Iterable<Import_MoM_Commission_Data__c> start(Database.BatchableContext BC) {
        try {
            List<Import__c> importRecords = [
                SELECT Id, Vendor__c, Date_range_start__c, Date_range_end__c
                FROM Import__c 
                WHERE Id = :importRecordId
                LIMIT 1
            ];

            if (importRecords.isEmpty()) {
                throw new CommissionImportException('Import record not found: ' + importRecordId);
            }

            Import__c importRecord = importRecords[0];
            this.strVendorId = importRecord.Vendor__c;
            this.startDate = importRecord.Date_range_start__c;
            this.endDate = importRecord.Date_range_end__c;

            validateImportData();

            return [
                SELECT Id, Dealer_Name__c, Commission_Amount__c, Data_Import_Status__c, 
                       Sales_Amount__c, Import__c 
                FROM Import_MoM_Commission_Data__c
                WHERE Import__c = :importRecordId
                AND Data_Import_Status__c = 'Inserted'
                LIMIT 10000
            ];

        } catch (Exception e) {
            this.errorMessage = 'Failed to initialize batch: ' + e.getMessage();
            return new List<Import_MoM_Commission_Data__c>();
        }
    }

    global void execute(Database.BatchableContext BC, List<Import_MoM_Commission_Data__c> records) {
        if (records == null || records.isEmpty()) return;

        try {
            ensureMoMReportExists();
            Map<String, Dealer_Journey_Alias__c> aliasMap = getDealerAliasMap();
            ProcessingResult result = processCommissionRecords(records, aliasMap);
            performDMLOperations(result);
            updateRunningTotals(result);
        } catch (Exception e) {
            this.errorMessage = 'Processing failed: ' + e.getMessage();
            this.totalErrors += records.size();
            throw e;
        }
    }

    global void finish(Database.BatchableContext BC) {
        try {
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error in finish method: ' + e.getMessage());
        }
    }

    private void validateImportData() {
        if (this.strVendorId == null) throw new CommissionImportException('Vendor ID is required');
        if (this.startDate == null || this.endDate == null) throw new CommissionImportException('Date range is required');
        if (this.endDate <= this.startDate) throw new CommissionImportException('End date must be after start date');
    }

    private void ensureMoMReportExists() {
        if (this.momReportId == null) {
            try {
                mom_report__c momReport = new mom_report__c(
                    mom_report_date__c = Date.today(),
                    Import__c = this.importRecordId,
                    Vendor__c = this.strVendorId,
                    invoice_date_start__c = this.startDate,
                    invoice_date_end__c = this.endDate,
                    invoice_commission_total__c = 0,
                    invoice_sales_total__c = 0
                );

                Database.SaveResult result = Database.insert(momReport, false);
                if (result.isSuccess()) {
                    this.momReportId = momReport.Id;
                } else {
                    throw new CommissionImportException('Failed to create MoM Report: ' + result.getErrors()[0].getMessage());
                }
            } catch (DmlException e) {
                throw new CommissionImportException('Failed to create MoM Report: ' + e.getMessage());
            }
        }
    }

    private Map<String, Dealer_Journey_Alias__c> getDealerAliasMap() {
        Map<String, Dealer_Journey_Alias__c> aliasMap = new Map<String, Dealer_Journey_Alias__c>();
        try {
            List<Dealer_Journey_Alias__c> aliases = [
                SELECT Name, Dealer__c, Vendor__c, Dealer_Journey__c 
                FROM Dealer_Journey_Alias__c 
                WHERE Vendor__c = :strVendorId
                LIMIT 10000
            ];

            for (Dealer_Journey_Alias__c alias : aliases) {
                if (String.isNotBlank(alias.Name)) {
                    String normalizedName = alias.Name.trim().toUpperCase();
                    if (!aliasMap.containsKey(normalizedName)) {
                        aliasMap.put(normalizedName, alias);
                    } else {
                        System.debug(LoggingLevel.WARN, 'Duplicate alias ignored: ' + normalizedName);
                    }
                }
            }

            return aliasMap;
        } catch (QueryException e) {
            throw new CommissionImportException('Failed to load dealer aliases: ' + e.getMessage());
        }
    }

    private ProcessingResult processCommissionRecords(List<Import_MoM_Commission_Data__c> records, Map<String, Dealer_Journey_Alias__c> aliasMap) {
        ProcessingResult result = new ProcessingResult();
        for (Import_MoM_Commission_Data__c record : records) {
            try {
                String normalizedName = String.isNotBlank(record.Dealer_Name__c) ? record.Dealer_Name__c.trim().toUpperCase() : '';
                if (String.isBlank(normalizedName)) {
                    record.Data_Import_Status__c = 'Skipped';
                    record.Error_Message__c = 'Dealer name is empty';
                    result.skippedRecords.add(record);
                    continue;
                }

                Dealer_Journey_Alias__c alias = aliasMap.get(normalizedName);
                if (alias != null && alias.Dealer__c != null) {
                    MoM_Commission__c commission = new MoM_Commission__c(
                        Dealer__c = alias.Dealer__c,
                        Vendor__c = this.strVendorId,
                        Dealer_Journey__c = alias.Dealer_Journey__c,
                        Import__c = this.importRecordId,
                        Sales_Amount__c = record.Sales_Amount__c != null ? record.Sales_Amount__c : 0,
                        Commission_Amount__c = record.Commission_Amount__c != null ? record.Commission_Amount__c : 0,
                        MoM_Report__c = this.momReportId
                    );

                    result.commissionsToInsert.add(commission);
                    record.Data_Import_Status__c = 'Processed';
                    record.Error_Message__c = null;
                    result.processedRecords.add(record);
                    result.batchCommissionTotal += commission.Commission_Amount__c;
                    result.batchSalesTotal += commission.Sales_Amount__c;
                } else {
                    record.Data_Import_Status__c = 'Skipped';
                    record.Error_Message__c = 'Dealer not found in aliases: ' + normalizedName;
                    result.skippedRecords.add(record);
                }
            } catch (Exception e) {
                record.Data_Import_Status__c = 'Error';
                record.Error_Message__c = 'Processing error: ' + e.getMessage();
                result.errorRecords.add(record);
            }
        }
        return result;
    }

    private void performDMLOperations(ProcessingResult result) {
        List<String> dmlErrors = new List<String>();
        try {
            if (!result.commissionsToInsert.isEmpty()) {
                Database.SaveResult[] commissionResults = Database.insert(result.commissionsToInsert, false);
                for (Integer i = 0; i < commissionResults.size(); i++) {
                    if (!commissionResults[i].isSuccess()) {
                        dmlErrors.add('Failed to insert commission: ' + commissionResults[i].getErrors()[0].getMessage());
                    }
                }
            }

            List<Import_MoM_Commission_Data__c> allToUpdate = new List<Import_MoM_Commission_Data__c>();
            allToUpdate.addAll(result.processedRecords);
            allToUpdate.addAll(result.skippedRecords);
            allToUpdate.addAll(result.errorRecords);

            if (!allToUpdate.isEmpty()) {
                Database.SaveResult[] updateResults = Database.update(allToUpdate, false);
                for (Integer i = 0; i < updateResults.size(); i++) {
                    if (!updateResults[i].isSuccess()) {
                        dmlErrors.add('Failed to update record: ' + updateResults[i].getErrors()[0].getMessage());
                    }
                }
            }

            if (!dmlErrors.isEmpty()) {
                System.debug(LoggingLevel.WARN, 'DML completed with ' + dmlErrors.size() + ' errors');
            }
        } catch (Exception e) {
            throw new CommissionImportException('DML operations failed: ' + e.getMessage());
        }
    }

    private void updateRunningTotals(ProcessingResult result) {
        this.totalProcessed += result.processedRecords.size();
        this.totalSkipped += result.skippedRecords.size();
        this.totalErrors += result.errorRecords.size();
    }

    private class ProcessingResult {
        public List<MoM_Commission__c> commissionsToInsert = new List<MoM_Commission__c>();
        public List<Import_MoM_Commission_Data__c> processedRecords = new List<Import_MoM_Commission_Data__c>();
        public List<Import_MoM_Commission_Data__c> skippedRecords = new List<Import_MoM_Commission_Data__c>();
        public List<Import_MoM_Commission_Data__c> errorRecords = new List<Import_MoM_Commission_Data__c>();
        public Decimal batchCommissionTotal = 0;
        public Decimal batchSalesTotal = 0;
    }

    public class CommissionImportException extends Exception {}
}