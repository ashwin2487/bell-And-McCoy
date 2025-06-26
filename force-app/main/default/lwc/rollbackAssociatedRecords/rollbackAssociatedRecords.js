import { LightningElement,api } from 'lwc';
import rollBackAssociatedRecords from '@salesforce/apex/rollBackAssociatedRecordsController.rollBackAssociatedRecords';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
export default class RollbackAssociatedRecords extends LightningElement {
        isProcessing = false;
        @api recordId;

    handleRollBack() {
            this.isProcessing = true;
            rollBackAssociatedRecords({ importRecordId: this.recordId })
            .then(jobId => {
                this.showToast('Success', `Batch started. Job ID: ${jobId}`, 'success');
            })
            .catch(error => {
                this.showToast('Error', error.body?.message || 'An error occurred', 'error');
            })
            .finally(() => {
                this.isProcessing = false;
            });
        }
    
        showToast(title, message, variant) {
            const event = new ShowToastEvent({
                title,
                message,
                variant
            });
            this.dispatchEvent(event);
        }
}