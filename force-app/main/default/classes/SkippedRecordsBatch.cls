public with sharing class SkippedRecordsBatch implements Database.Batchable<SObject>, Database.Stateful {
    
    private Id importRecordId;
    private String vendorId;
    
    public SkippedRecordsBatch(Id importRecordId) {
        this.importRecordId = importRecordId;
    }
    
    public Database.QueryLocator start(Database.BatchableContext bc) {
        String query = 'SELECT Id, Dealer_Name__c, Invoice_Date__c, Invoice_Number__c, Product_SKU__c, Product_Quantity__c, ' +
            'Unit_Price__c, Commission_Received__c, Account_Number__c, Import__c, Vendor__c, ' +
            'Data_Import_Status__c, PO_Number__c, Job_Name__c, Project__c, Batch_Id__c, Batch_Id_2__c ' +
            'FROM Dealer_Import_Data__c ' +
            'WHERE Import__c = : importRecordId ' +
            'AND Data_Import_Status__c != \'Processed\'';
        
        List<Dealer_Import_Data__c> importRecords = Database.query(query);
        
        if (importRecords.isEmpty()) {
            User currentUser = [SELECT Email FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
            email.setToAddresses(new String[] { currentUser.Email, 'cclarke@bellandmccoy.com' });
            email.setSubject('No Dealer Import Data Found to process');
            email.setPlainTextBody('No Dealer Import Data records were found to process for the specified Import record ID: ' + importRecordId);
            Messaging.sendEmail(new Messaging.SingleEmailMessage[] { email });
            
            return Database.getQueryLocator([SELECT Id FROM Dealer_Import_Data__c WHERE Id = NULL]);
        }
        
        vendorId = importRecords[0].Vendor__c;
        return Database.getQueryLocator(query);
    }
    
    public void execute(Database.BatchableContext BC, List<Dealer_Import_Data__c> skippedRecords) {
        if (skippedRecords.isEmpty()) return;
        
        String batchJobId = BC.getJobId();
        
        Map<String, Dealer_Invoice__c> invoiceNumberMap = new Map<String, Dealer_Invoice__c>();
        Map<String, Dealer_Invoice__c> newInvoiceNumberMap = new Map<String, Dealer_Invoice__c>();
        Set<String> journeyIds = new Set<String>();
        Set<String> existingInvoiceNumbers = new Set<String>();
        Map<String, String> dealerNameToJourneyId = new Map<String, String>();
        Map<String, Id> recordTypeMap = new Map<String, Id>();
        Map<String, String> journeyToDealerMap = new Map<String, String>();
        Set<String> productSKUs = new Set<String>();
        Map<String, Account_Number__c> accountNumberMap = new Map<String, Account_Number__c>();
        
        List<Dealer_Import_Data__c> toUpdate = new List<Dealer_Import_Data__c>();
        List<Dealer_Import_Data__c> skippedDealerDetailsForNotMatchingAlias = new List<Dealer_Import_Data__c>();
        List<Dealer_Import_Data__c> skippedDealerDetailsForNullAccNum = new List<Dealer_Import_Data__c>();
        List<Dealer_Import_Data__c> matchedNonNullAccountNumberRecords = new List<Dealer_Import_Data__c>();
        List<Dealer_Import_Data__c> nonMatchedNonNullAccountNumberRecords = new List<Dealer_Import_Data__c>();
        List<Dealer_Import_Data__c> exactMatchedRecordsWithBothAccNumAndDJ = new List<Dealer_Import_Data__c>();
        List<Dealer_Journey_Alias__c> toInsertList = new List<Dealer_Journey_Alias__c>();
        List<Dealer_Invoice_Line__c> lineItems = new List<Dealer_Invoice_Line__c>();
        Map<String, Dealer_Invoice__c> newInvoicesMap = new Map<String, Dealer_Invoice__c>();
        
        for (RecordType rt : [SELECT Id, DeveloperName FROM RecordType WHERE SObjectType IN ('Account', 'Dealer_Journey__c', 'Import__c')]) {
            recordTypeMap.put(rt.DeveloperName, rt.Id);
        }
        
        for (Dealer_Journey_Alias__c alias : [SELECT Id, Name, Dealer_Journey__c FROM Dealer_Journey_Alias__c WHERE Vendor__c = :vendorId]) {
            String normalizedName = alias.Name != null ? alias.Name.trim().toUpperCase() : '';
            dealerNameToJourneyId.put(normalizedName, alias.Dealer_Journey__c);
        }
        
        for (Account_Number__c acc : [SELECT Id, Account_Number__c, Dealer_Journey__c FROM Account_Number__c WHERE Vendor__c = :vendorId]) {
            String normalizedAccNum = acc.Account_Number__c != null ? acc.Account_Number__c.trim().toUpperCase() : '';
            accountNumberMap.put(normalizedAccNum, acc);
        }
        
        Set<String> aliasNamesToInsert = new Set<String>();
        
        for (Dealer_Import_Data__c record : skippedRecords) {
            String normalizedAlias = record.Dealer_Name__c != null ? record.Dealer_Name__c.trim().toUpperCase() : '';
            String normalizedSKU = record.Product_SKU__c != null ? record.Product_SKU__c.trim().toUpperCase() : null;
            String normalizedAccNum = record.Account_Number__c != null ? record.Account_Number__c.trim().toUpperCase() : null;
            String normalizedInvoiceNum = record.Invoice_Number__c != null ? record.Invoice_Number__c.trim().toUpperCase() : null;
            
            if (normalizedSKU != null) productSKUs.add(normalizedSKU);
            Boolean hasAlias = dealerNameToJourneyId.containsKey(normalizedAlias);
            
            if (normalizedAccNum != null && accountNumberMap.containsKey(normalizedAccNum)) {
                matchedNonNullAccountNumberRecords.add(record);
                
                if (hasAlias) {
                    exactMatchedRecordsWithBothAccNumAndDJ.add(record);
                    existingInvoiceNumbers.add(normalizedInvoiceNum);
                    journeyIds.add(dealerNameToJourneyId.get(normalizedAlias));
                } else {
                    skippedDealerDetailsForNotMatchingAlias.add(record);
                    
                    if (!aliasNamesToInsert.contains(normalizedAlias)) {
                        aliasNamesToInsert.add(normalizedAlias);
                        Account_Number__c acc = accountNumberMap.get(normalizedAccNum);
                        if (acc != null && acc.Dealer_Journey__c != null) {
                            toInsertList.add(new Dealer_Journey_Alias__c(
                                Dealer_Journey__c = acc.Dealer_Journey__c,
                                Name = record.Dealer_Name__c,
                                Vendor__c = vendorId,
                                Import__c = importRecordId,
                                Batch_Id__c = batchJobId
                            ));
                        }
                    }
                }
            } else if (hasAlias) {
                exactMatchedRecordsWithBothAccNumAndDJ.add(record);
                existingInvoiceNumbers.add(normalizedInvoiceNum);
                journeyIds.add(dealerNameToJourneyId.get(normalizedAlias));
            } else {
                skippedDealerDetailsForNullAccNum.add(record);
            }
        }
        
        if (!toInsertList.isEmpty()) {
            try {
                insert toInsertList;
            } catch (Exception ex) {
                System.debug('Error inserting Dealer_Journey_Alias__c records: ' + ex.getMessage());
            }
            for (Dealer_Journey_Alias__c alias : toInsertList) {
                String normalizedName = alias.Name != null ? alias.Name.trim().toUpperCase() : '';
                dealerNameToJourneyId.put(normalizedName, alias.Dealer_Journey__c);
            }
        }
        
        Map<String, Product2> productSKUMap = new Map<String, Product2>();
        for (Product2 p : [SELECT Id, StockKeepingUnit, Name FROM Product2 WHERE Vendor__c = :vendorId]) {
            if (p.StockKeepingUnit != null) productSKUMap.put(p.StockKeepingUnit.trim().toUpperCase(), p);
        }
        
        List<Product2> newProducts = new List<Product2>();
        for (String sku : productSKUs) {
            if (!productSKUMap.containsKey(sku)) {
                newProducts.add(new Product2(Name = sku, StockKeepingUnit = sku, Vendor__c = vendorId, Import__c = importRecordId, Batch_Id__c = batchJobId));
            }
        }
        
        if (!newProducts.isEmpty()) {
            insert newProducts;
            for (Product2 p : newProducts) productSKUMap.put(p.StockKeepingUnit.trim().toUpperCase(), p);
        }
        
        Id activeRTId = Schema.SObjectType.Dealer_Journey__c.getRecordTypeInfosByDeveloperName().get('Active').getRecordTypeId();
        List<Dealer_Journey__c> journeysToUpdate = new List<Dealer_Journey__c>();
        for (Dealer_Journey__c j : [SELECT Id, RecordTypeId, Active__c FROM Dealer_Journey__c WHERE Id IN :journeyIds]) {
            if (j.RecordTypeId != activeRTId || !j.Active__c) {
                j.RecordTypeId = activeRTId;
                j.Active__c = true;
                j.Activation_Date__c = System.today();
                journeysToUpdate.add(j);
            }
        }
        if (!journeysToUpdate.isEmpty()) update journeysToUpdate;
        
        for (Dealer_Journey__c j : [SELECT Id, Dealer__c FROM Dealer_Journey__c WHERE Id IN :journeyIds]) {
            journeyToDealerMap.put(j.Id, j.Dealer__c);
        }
        
        for (Dealer_Invoice__c inv : [
            SELECT Id, Invoice_Number__c FROM Dealer_Invoice__c 
            WHERE Invoice_Number__c IN :existingInvoiceNumbers AND Vendor__c = :vendorId
        ]) {
            invoiceNumberMap.put(inv.Invoice_Number__c.trim().toUpperCase(), inv);
        }
        
        for (Dealer_Import_Data__c record : skippedRecords) {
            String invoiceNum = record.Invoice_Number__c != null ? record.Invoice_Number__c.trim().toUpperCase() : null;
            String sku = record.Product_SKU__c != null ? record.Product_SKU__c.trim().toUpperCase() : null;
            Id productId = sku != null && productSKUMap.containsKey(sku) ? productSKUMap.get(sku).Id : null;
            String normalizedAlias = record.Dealer_Name__c != null ? record.Dealer_Name__c.trim().toUpperCase() : '';
            Id journeyId = dealerNameToJourneyId.get(normalizedAlias);
            Id dealerId = journeyToDealerMap.get(journeyId);
            Id accId = record.Account_Number__c != null ? accountNumberMap.get(record.Account_Number__c?.trim().toUpperCase())?.Id : null;
            
            if (invoiceNum != null && invoiceNumberMap.containsKey(invoiceNum)) {
                lineItems.add(new Dealer_Invoice_Line__c(
                    Dealer_Invoice__c = invoiceNumberMap.get(invoiceNum).Id,
                    Invoice_Date__c = record.Invoice_Date__c,
                    Invoice_Number__c = record.Invoice_Number__c,
                    Quantity__c = record.Product_Quantity__c,
                    Product__c = productId,
                    Amount_Each__c = record.Unit_Price__c,
                    Commission_Amount_Each__c = record.Commission_Received__c,
                    Import__c = importRecordId,
                    Batch_Id_2__c = batchJobId
                ));
            } else if (journeyId != null && dealerId != null) {
                Dealer_Invoice__c newInv = new Dealer_Invoice__c(
                    Invoice_Date__c = record.Invoice_Date__c,
                    Invoice_Number__c = record.Invoice_Number__c,
                    Dealer__c = dealerId,
                    Vendor__c = vendorId,
                    Import__c = importRecordId,
                    Dealer_Journey__c = journeyId,
                    PO_Number__c = record.PO_Number__c,
                    Job_Name__c = record.Job_Name__c,
                    Project__c = record.Project__c,
                    Batch_Id_2__c = batchJobId
                );
                if (accId != null) newInv.Account_Number__c = accId;
                newInvoicesMap.put(invoiceNum, newInv);
            }
        }
        
        if (!newInvoicesMap.isEmpty()) insert newInvoicesMap.values();
        for (Dealer_Invoice__c inv : newInvoicesMap.values()) {
            newInvoiceNumberMap.put(inv.Invoice_Number__c.trim().toUpperCase(), inv);
        }
        
        for (Dealer_Import_Data__c record : skippedRecords) {
            String invoiceNum = record.Invoice_Number__c != null ? record.Invoice_Number__c.trim().toUpperCase() : null;
            if (invoiceNum != null && newInvoiceNumberMap.containsKey(invoiceNum)) {
                Id productId = record.Product_SKU__c != null ? productSKUMap.get(record.Product_SKU__c.trim().toUpperCase())?.Id : null;
                lineItems.add(new Dealer_Invoice_Line__c(
                    Dealer_Invoice__c = newInvoiceNumberMap.get(invoiceNum).Id,
                    Invoice_Date__c = record.Invoice_Date__c,
                    Invoice_Number__c = record.Invoice_Number__c,
                    Quantity__c = record.Product_Quantity__c,
                    Product__c = productId,
                    Amount_Each__c = record.Unit_Price__c,
                    Commission_Amount_Each__c = record.Commission_Received__c,
                    Import__c = importRecordId,
                    Batch_Id_2__c = batchJobId
                ));
            }
        }
        
        if (!lineItems.isEmpty()) insert lineItems;
        
        // Update status
        for (Dealer_Import_Data__c record : skippedRecords) {
            String invoiceNum = record.Invoice_Number__c != null ? record.Invoice_Number__c.trim().toUpperCase() : null;
            if (invoiceNum != null && (invoiceNumberMap.containsKey(invoiceNum) || newInvoiceNumberMap.containsKey(invoiceNum))) {
                record.Data_Import_Status__c = 'Processed';
                record.Batch_Id_2__c = batchJobId;
                toUpdate.add(record);
            }
        }
        
        for (Dealer_Import_Data__c skipped : skippedDealerDetailsForNullAccNum) {
            String inv = skipped.Invoice_Number__c != null ? skipped.Invoice_Number__c.trim().toUpperCase() : null;
            if (inv != null && !invoiceNumberMap.containsKey(inv) && !newInvoiceNumberMap.containsKey(inv)) {
                skipped.Data_Import_Status__c = 'Account Number - Null';
                toUpdate.add(skipped);
            }
        }
        
        for (Dealer_Import_Data__c skipped : skippedDealerDetailsForNotMatchingAlias) {
            String inv = skipped.Invoice_Number__c != null ? skipped.Invoice_Number__c.trim().toUpperCase() : null;
            if (inv != null && !invoiceNumberMap.containsKey(inv) && !newInvoiceNumberMap.containsKey(inv)) {
                skipped.Data_Import_Status__c = 'Dealer Alias - Created New';
                toUpdate.add(skipped);
            }
        }
        
        if (!toUpdate.isEmpty()) update toUpdate;
    }
    
    public void finish(Database.BatchableContext BC) {
        try {
            String batchJobId = BC.getJobId();
            Integer processed = [SELECT COUNT() FROM Dealer_Import_Data__c WHERE Import__c = :importRecordId AND Data_Import_Status__c = 'Processed' AND Batch_Id_2__c = :batchJobId];
            Integer invs = [SELECT COUNT() FROM Dealer_Invoice__c WHERE Import__c = :importRecordId AND Batch_Id_2__c = :batchJobId];
            Integer lines = [SELECT COUNT() FROM Dealer_Invoice_Line__c WHERE Import__c = :importRecordId AND Batch_Id_2__c = :batchJobId];
            Integer prods = [SELECT COUNT() FROM Product2 WHERE Import__c = :importRecordId AND Batch_Id__c = :batchJobId];
            String vendorName = [SELECT Name FROM Vendor__c WHERE Id = :vendorId].Name;
            
            insert new Batch_Process_Summary__c(
                Import_Record__c = importRecordId,
                Batch_Job_Id__c = batchJobId,
                Total_Records_Processed__c = processed,
                Total_Invoices_Inserted__c = invs,
                Total_Invoice_Lines_Inserted__c = lines,
                Total_Products_Inserted__c = prods
            );
            
            String body = String.format('Skipped Records Batch Job Completed.\n\nVendor: {0}\nImport Record ID: {1}\n\nTotal Dealer Import Records Processed: {2}\nTotal Invoices Inserted: {3}\nTotal Invoice Line Items Inserted: {4}\n\nTotal Products Inserted: {5}\nJob ID: {6}\n\nCompleted on: {7}',
                                        new Object[]{vendorName, importRecordId, processed, invs, lines, prods, batchJobId, System.now().format()});
            
            User currentUser = [SELECT Email FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
            
            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setToAddresses(new String[]{currentUser.Email, 'cclarke@bellandmccoy.com'});
            mail.setSubject('Skipped Records Batch Job Summary');
            mail.setPlainTextBody(body);
            Messaging.sendEmail(new Messaging.SingleEmailMessage[]{mail});
        } catch (Exception e) {
            System.debug('Error sending summary email: ' + e.getMessage());
            System.debug(e.getStackTraceString());
        }
    }
}