import { LightningElement, track, api } from 'lwc';
import { loadScript } from 'lightning/platformResourceLoader';
import PapaParse from '@salesforce/resourceUrl/PapaParse';
 
import insertDealerData from '@salesforce/apex/DealerImportProcess.insertDealerData';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
 
export default class DealerImportProcess extends LightningElement {
    @api recordId;
    @track isLoaded = false;
    @track showFileUpload = true;
    @track totalChunks = 0;
    @track completedChunks = 0;
    @track progressPercent = 0;
    @track totalInserted = 0;
    @track fileName = ''; // To display the file name being processed
 
    papaLoaded = false;
 
    renderedCallback() {
        if (this.papaLoaded) return;
 
        loadScript(this, PapaParse)
            .then(() => {
                this.papaLoaded = true;
            })
            .catch(error => {
                this.showToast('Error loading parser', error.message, 'error');
            });
    }
 
    get circularProgressStyle() {
        // Radius of the circle in the SVG
        const radius = 40;
        // Circumference of the circle
        const circumference = 2 * Math.PI * radius;
        // Calculate the offset based on the progress percentage
        // (100 - progressPercent) because stroke-dashoffset works inversely
        const offset = circumference - (this.progressPercent / 100) * circumference;
 
        return `
            stroke-dasharray: ${circumference} ${circumference};
            stroke-dashoffset: ${offset};
            transition: stroke-dashoffset 0.3s ease-in-out;
        `;
    }
 
    handleBrowseClick() {
        this.template.querySelector('input[data-id="fileInput"]').click();
    }
 
    handleFileChange(event) {
        if (!this.papaLoaded) {
            this.showToast('Error', 'PapaParse library not loaded yet.', 'error');
            return;
        }
 
        const file = event.target.files[0];
        if (!file) {
            this.showToast('Error', 'Please upload a valid CSV file.', 'error');
            return;
        }
        this.fileName = file.name; // Set the file name for display
 
        this.isLoaded = true;
        this.showFileUpload = false;
 
        const reader = new FileReader();
 
        reader.onload = async () => {
            try {
                const csv = reader.result;
 
                const results = Papa.parse(csv, {
                    header: true,
                    skipEmptyLines: true
                });
 
                const records = results.data;
                const totalRecords = records.length;
 
                if (!records || totalRecords === 0) {
                    this.showToast('Error', 'CSV file is empty or invalid.', 'error');
                    this.resetUI();
                    return;
                }
 
                const chunks = this.chunkArray(records, 500);
                this.totalChunks = chunks.length;
                this.completedChunks = 0;
                this.totalInserted = 0;
 
                let currentLineNumber = 1;
 
                for (let i = 0; i < chunks.length; i++) {
                    const chunk = chunks[i];
 
                    for (let j = 0; j < chunk.length; j++) {
                        chunk[j].Line_Number__c = currentLineNumber++;
                    }
 
                    const startLine = currentLineNumber - chunk.length;
                    const endLine = currentLineNumber - 1;
 
                    const insertedCount = await this.uploadChunk(chunk, startLine, endLine);
                    this.totalInserted += insertedCount;
 
                    this.completedChunks++;
                    this.progressPercent = Math.floor((this.completedChunks / this.totalChunks) * 100);
                }
 
                this.showToast(
                    'Upload Complete',
                    `${this.totalInserted} records inserted in ${this.totalChunks} chunks.`,
                    'success'
                );
            } catch (error) {
                this.showToast('Upload Error', error.body?.message || error.message || 'An unknown error occurred.', 'error');
            }
 
            this.resetUI();
        };
 
        reader.readAsText(file);
    }
 
    handleDrop(event) {
        event.preventDefault();
        event.stopPropagation();
        const files = event.dataTransfer.files;
        if (files.length > 0) {
            this.handleFileChange({ target: { files: [files[0]] } });
        }
    }
 
    handleDragOver(event) {
        event.preventDefault();
        event.stopPropagation();
    }
 
    chunkArray(array, size) {
        const chunks = [];
        for (let i = 0; i < array.length; i += size) {
            chunks.push(array.slice(i, i + size));
        }
        return chunks;
    }
 
    async uploadChunk(chunk, startLine, endLine) {
        try {
            return await insertDealerData({
                records: chunk,
                importRecordId: this.recordId,
                startLine,
                endLine
            });
        } catch (error) {
            this.showToast(`Error uploading lines ${startLine}-${endLine}`, error.body?.message || 'Upload failed.', 'error');
            return 0;
        }
    }
 
    resetUI() {
        this.isLoaded = false;
        this.showFileUpload = true;
        this.progressPercent = 0;
        this.fileName = '';
    }
 
    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}