global class UpdateMoMReportProcess implements Database.Batchable<mom_report__c>, Database.Stateful {
    
    @TestVisible private Id momReportId;
    @TestVisible private Integer batchSize;
    @TestVisible private Id strVendorId;
    @TestVisible private Date startDate;
    @TestVisible private Date endDate;
    @TestVisible private Id importRecordId;
    @TestVisible private String errorMessage;
    @TestVisible private Integer recordsProcessed = 0;
    
    public UpdateMoMReportProcess(Id momReportId, Integer batchSize) {
        this.momReportId = momReportId;
        this.batchSize = batchSize;
    }
    
    global Iterable<mom_report__c> start(Database.BatchableContext BC) {
        try {
            return [SELECT Id, invoice_date_end__c, invoice_commission_total__c, 
                    invoice_sales_total__c, invoice_date_start__c, Import__c, 
                    Import__r.RecordTypeId, mom_report_date__c, Vendor__c
                    FROM mom_report__c 
                    WHERE Id = :momReportId];
        } catch (Exception e) {
            System.debug('Error in start method: ' + e.getMessage());
            this.errorMessage = 'Failed to retrieve MoM Report: ' + e.getMessage();
            return new List<mom_report__c>();
        }
    }
    
    global void execute(Database.BatchableContext BC, List<mom_report__c> records) {
        if (records == null || records.isEmpty()) {
            System.debug('No records to process in execute method');
            return;
        }
        
        try {
            mom_report__c momRecord = records[0];
            this.strVendorId = momRecord.Vendor__c;
            this.startDate = momRecord.invoice_date_start__c;
            this.endDate = momRecord.invoice_date_end__c;
            this.importRecordId = momRecord.Import__c;
            
            if (this.strVendorId == null || this.startDate == null || 
                this.endDate == null || this.importRecordId == null) {
                    throw new UpdateMoMReportException('Missing required data: Vendor, Start Date, End Date, or Import Record');
                }
            
            processCommissionUpdates();
            
        } catch (Exception e) {
            System.debug('Error in execute method: ' + e.getMessage());
            this.errorMessage = 'Processing failed: ' + e.getMessage();
            throw e; 
        }
    }
    private void processCommissionUpdates() {
        Map<Id, MoM_Commission__c> momCommissionMap = getMoMCommissions();
        if (momCommissionMap.isEmpty()) {
            System.debug('No MoM Commission records found');
            return;
        }
        
        Set<Id> dealerIdSet = getDealerIds(momCommissionMap.values());
        if (dealerIdSet.isEmpty()) {
            System.debug('No dealer IDs found');
            return;
        }
        Map<Id, Id> invoiceIdToDealerIdMap = getInvoiceToDealerMapping(dealerIdSet);
        if (invoiceIdToDealerIdMap.isEmpty()) {
            System.debug('No invoices found for the specified criteria');
            return;
        }
        
        Decimal totalSales = 0;
        Decimal totalCommission = 0;
        
        for (Dealer_Invoice_Line__c line : [
            SELECT amount_total__c, commission_total__c, Dealer_Invoice__c
            FROM Dealer_Invoice_Line__c
            WHERE Dealer_Invoice__c IN :invoiceIdToDealerIdMap.keySet()
            LIMIT 10000
        ]) {
            totalSales += line.amount_total__c != null ? line.amount_total__c : 0;
            totalCommission += line.commission_total__c != null ? line.commission_total__c : 0;
        }
        
        try {
            mom_report__c reportToUpdate = new mom_report__c(
                Id = this.momReportId,
                invoice_sales_total__c = totalSales,
                invoice_commission_total__c = totalCommission
            );
            update reportToUpdate;
            this.recordsProcessed = 1;
            System.debug('Updated mom_report__c totals successfully.');
        } catch (Exception e) {
            System.debug('Error updating mom_report__c totals: ' + e.getMessage());
            this.errorMessage = 'Failed to update mom_report__c totals: ' + e.getMessage();
        }
    }
    
    
    private Map<Id, MoM_Commission__c> getMoMCommissions() {
        Map<Id, MoM_Commission__c> momCommissionMap = new Map<Id, MoM_Commission__c>();
        
        for (MoM_Commission__c curRecord : [
            SELECT Id, Dealer__c, Commission_Amount__c, Sales_Amount__c
            FROM MoM_Commission__c 
            WHERE Vendor__c = :strVendorId 
            AND Import__c = :importRecordId 
            AND MoM_Report__c = :momReportId
            LIMIT 10000
        ]) {
            momCommissionMap.put(curRecord.Id, curRecord);
        }
        
        return momCommissionMap;
    }
    
    private Set<Id> getDealerIds(List<MoM_Commission__c> commissions) {
        Set<Id> dealerIdSet = new Set<Id>();
        for (MoM_Commission__c commission : commissions) {
            if (commission.Dealer__c != null) {
                dealerIdSet.add(commission.Dealer__c);
            }
        }
        return dealerIdSet;
    }
    
    private Map<Id, Id> getInvoiceToDealerMapping(Set<Id> dealerIdSet) {
        Map<Id, Id> invoiceIdToDealerIdMap = new Map<Id, Id>();
        
        for (Dealer_Invoice__c inv : [
            SELECT Id, Dealer__c 
            FROM Dealer_Invoice__c 
            WHERE Vendor__c = :strVendorId 
            AND Import__c = :importRecordId 
            AND Invoice_Date__c >= :startDate
            AND Invoice_Date__c <= :endDate
            AND Dealer__c IN :dealerIdSet
            LIMIT 10000 // Add governor limit protection
        ]) {
            invoiceIdToDealerIdMap.put(inv.Id, inv.Dealer__c);
        }
        
        return invoiceIdToDealerIdMap;
    }
    
    private Map<Id, AggregateData> calculateDealerTotals(Map<Id, Id> invoiceIdToDealerIdMap) {
        Map<Id, AggregateData> dealerAggregates = new Map<Id, AggregateData>();
        
        for (Dealer_Invoice_Line__c line : [
            SELECT amount_total__c, commission_total__c, Dealer_Invoice__c
            FROM Dealer_Invoice_Line__c
            WHERE Dealer_Invoice__c IN :invoiceIdToDealerIdMap.keySet()
            LIMIT 10000 // Add governor limit protection
        ]) {
            Id dealerId = invoiceIdToDealerIdMap.get(line.Dealer_Invoice__c);
            if (dealerId == null) continue;
            
            Decimal sales = line.amount_total__c != null ? line.amount_total__c : 0;
            Decimal commission = line.commission_total__c != null ? line.commission_total__c : 0;
            
            if (!dealerAggregates.containsKey(dealerId)) {
                dealerAggregates.put(dealerId, new AggregateData());
            }
            
            AggregateData aggregate = dealerAggregates.get(dealerId);
            aggregate.totalSales += sales;
            aggregate.totalCommission += commission;
        }
        
        return dealerAggregates;
    }
    global void finish(Database.BatchableContext BC) {
        System.debug('UpdateMoMReportProcess completed. Records processed: ' + this.recordsProcessed);
        
        if (this.errorMessage != null) {
            System.debug('Batch completed with errors: ' + this.errorMessage);
        }
        
    }
    
    private class AggregateData {
        public Decimal totalSales = 0;
        public Decimal totalCommission = 0;
    }
    
    public class UpdateMoMReportException extends Exception {}
}