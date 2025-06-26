public class rollbackAssociatedRecordsBatch implements Database.Batchable<SObject> {
    private Id importRecordId;
    
    public rollbackAssociatedRecordsBatch(Id importRecordId) {
        this.importRecordId = importRecordId;
    }
    
    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, Dealer_Name__c, Invoice_Number__c, Product_SKU__c, Vendor__c, Batch_Id__c, Batch_Id_2__c
            FROM Dealer_Import_Data__c
            WHERE Import__c = :importRecordId
        ]);
    }
    
    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        List<Dealer_Import_Data__c> importRecords = (List<Dealer_Import_Data__c>) scope;
        
        // 1) Gather context
        Set<String> invoiceNumbers = new Set<String>();
        Set<String> productSKUs    = new Set<String>();
        Set<String> dealers        = new Set<String>();
        Set<String> vendors        = new Set<String>();
        Set<String> batchId1       = new Set<String>();
        Set<String> batchId2       = new Set<String>();
        
        for (Dealer_Import_Data__c rec : importRecords) {
            if (rec.Invoice_Number__c != null) invoiceNumbers.add(rec.Invoice_Number__c);
            if (rec.Product_SKU__c     != null) productSKUs.add(rec.Product_SKU__c);
            if (rec.Dealer_Name__c     != null) dealers.add(rec.Dealer_Name__c);
            if (rec.Vendor__c          != null) vendors.add(rec.Vendor__c);
            if (rec.Batch_Id__c        != null) batchId1.add(rec.Batch_Id__c);
            if (rec.Batch_Id_2__c      != null) batchId2.add(rec.Batch_Id_2__c);
        }
        
        try {
            // 2) Delete Dealer_Journey_Alias__c
            List<Dealer_Journey_Alias__c> djAliasToDelete = [
                SELECT Id
                FROM Dealer_Journey_Alias__c
                WHERE (Name IN :dealers AND Vendor__c IN :vendors AND Import__c = :importRecordId)
                   OR Batch_Id__c IN :batchId1
            ];
            
            // 3) Delete all invoice lines & invoices
            List<Dealer_Invoice_Line__c> invoiceLinesToDelete = [
                SELECT Id
                FROM Dealer_Invoice_Line__c
                WHERE Invoice_Number__c IN :invoiceNumbers
            ];
            List<Dealer_Invoice__c> invoicesToDelete = [
                SELECT Id
                FROM Dealer_Invoice__c
                WHERE Invoice_Number__c IN :invoiceNumbers
            ];
            
            // 4) Load candidate products
            List<Product2> candidateProducts = new List<Product2>();
            if (!productSKUs.isEmpty()) {
                candidateProducts = [
                    SELECT Id, StockKeepingUnit
                    FROM Product2
                    WHERE (StockKeepingUnit IN :productSKUs OR Name IN :productSKUs)
                      AND Vendor__c IN :vendors
                      AND Import__c = :importRecordId
                ];
            }
            
            // 5) Find any “outside” usage
            Set<Id> productIds = new Set<Id>();
            for (Product2 p : candidateProducts) productIds.add(p.Id);
            
            List<Dealer_Invoice_Line__c> lines = productIds.isEmpty()
                ? new List<Dealer_Invoice_Line__c>()
                : [
                    SELECT Product__c, Batch_Id__c, Batch_Id_2__c, Import__c, Invoice_Number__c
                    FROM Dealer_Invoice_Line__c
                    WHERE Product__c IN :productIds
                  ];
            
            List<Dealer_Invoice__c> invoices = invoiceNumbers.isEmpty()
                ? new List<Dealer_Invoice__c>()
                : [
                    SELECT Invoice_Number__c, Batch_Id__c, Batch_Id_2__c, Import__c
                    FROM Dealer_Invoice__c
                    WHERE Invoice_Number__c IN :invoiceNumbers
                  ];
            
            Set<Id> usedElsewhere = new Set<Id>();
            
            // a) by line
            for (Dealer_Invoice_Line__c line : lines) {
                Boolean outsideBatch  = !batchId1.contains(line.Batch_Id__c) && !batchId2.contains(line.Batch_Id_2__c);
                Boolean outsideImport = line.Import__c != importRecordId;
                if (outsideBatch || outsideImport) {
                    usedElsewhere.add(line.Product__c);
                }
            }
            
            // b) by invoice
            Set<String> badInvoices = new Set<String>();
            for (Dealer_Invoice__c inv : invoices) {
                Boolean invOutsideBatch  = !batchId1.contains(inv.Batch_Id__c) && !batchId2.contains(inv.Batch_Id_2__c);
                Boolean invOutsideImport = inv.Import__c != importRecordId;
                if (invOutsideBatch || invOutsideImport) {
                    badInvoices.add(inv.Invoice_Number__c);
                }
            }
            for (Dealer_Invoice_Line__c line : lines) {
                if (badInvoices.contains(line.Invoice_Number__c)) {
                    usedElsewhere.add(line.Product__c);
                }
            }
            
            // 6) Final product deletion list
            List<Product2> productRecordsToDelete = new List<Product2>();
            for (Product2 p : candidateProducts) {
                if (!usedElsewhere.contains(p.Id)) {
                    productRecordsToDelete.add(p);
                }
            }
            
            // 7) Perform deletions
            if (!djAliasToDelete.isEmpty())        delete djAliasToDelete;
            if (!invoiceLinesToDelete.isEmpty())   delete invoiceLinesToDelete;
            if (!invoicesToDelete.isEmpty())       delete invoicesToDelete;
            if (!productRecordsToDelete.isEmpty()) delete productRecordsToDelete;
            if (!importRecords.isEmpty())          delete importRecords;
            
        } catch (Exception e) {
            sendErrorEmail('Rollback Batch Failed', 'Error during rollback deletion: ' + e.getMessage());
        }
    }
    
    public void finish(Database.BatchableContext bc) {
        sendEmail(
            'Rollback Batch Completed',
            'The rollback batch has completed successfully for Import__c record: ' + importRecordId
        );
    }
    
    private void sendEmail(String subject, String body) {
        try {
            String userEmail = [
                SELECT Email
                FROM User
                WHERE Id = :UserInfo.getUserId()
                LIMIT 1
            ].Email;
            
            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
            email.setToAddresses(new String[]{ userEmail, 'cclarke@bellandmccoy.com' });
            email.setSubject(subject);
            email.setPlainTextBody(body);
            Messaging.sendEmail(new Messaging.SingleEmailMessage[]{ email });
            
        } catch (Exception e) {
            System.debug('Failed to send email: ' + e.getMessage());
        }
    }
    
    private void sendErrorEmail(String subject, String body) {
        sendEmail(subject, body);
    }
}