public with sharing class deleteDealerImportDataBatch implements Database.Batchable<SObject> {
    private Id importRecordId;

    public deleteDealerImportDataBatch(Id importRecordId) {
        this.importRecordId = importRecordId;
    }
    
    public Database.QueryLocator start(Database.BatchableContext bc) {
        
        String query = 'SELECT Id FROM Dealer_Import_Data__c WHERE Import__c = :importRecordId';
        
        List<Dealer_Import_Data__c> importRecords = Database.query(query);
        
        if (importRecords.isEmpty()) {
            User currentUser = [
                SELECT Email FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1
            ];
            
            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
            email.setToAddresses(new String[] { currentUser.Email, 'cclarke@bellandmccoy.com' });
            email.setSubject('No Dealer Import Data Found to delete.');
            email.setPlainTextBody('No Dealer Import Data records were found to delete for the specified Import record ID: ' + importRecordId);
            Messaging.sendEmail(new Messaging.SingleEmailMessage[] { email });
            
            return Database.getQueryLocator([SELECT Id FROM Dealer_Import_Data__c WHERE Id = NULL]);
        }
        
        return Database.getQueryLocator(query);
    }

    public void execute(Database.BatchableContext bc, List<Dealer_Import_Data__c> scope) {
        System.debug('Batch executing with ' + scope.size() + ' records.');
        try {
            delete scope;
        } catch (Exception e) {
            throw new AuraHandledException('Error deleting records: ' + e.getMessage());
        }
    }
    

    public void finish(Database.BatchableContext bc) {
        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        User currentUser = [
            SELECT Email FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1
        ];
        
        email.setToAddresses(new String[] { currentUser.Email ,'cclarke@bellandmccoy.com' });
        email.setSubject('Rollback Batch Completed');
        email.setPlainTextBody('The Dealer Import Data - Temporary Data, Delete batch has completed successfully for Import__c record: ' + importRecordId);
        
        Messaging.sendEmail(new Messaging.SingleEmailMessage[] { email });
    }
    
}