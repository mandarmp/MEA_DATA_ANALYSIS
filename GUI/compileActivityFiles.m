% This script goes through the h5 files in a parent folder,
% plot the Rasters, FiringRate Maps, and, Amplitude Maps
% and compile a csv with the mean Firing Rate and Amplitude over days


function [] = compileActivityFiles(data)


mfilename('fullpath')
fileDir = [pwd,'/',mfilename];




%ui components.
fig =data.fig;
d = uiprogressdlg(fig,'Title','Compiling files',...
    'Message','Start','Cancelable','on');
drawnow
logFile = data.logFile;
% Unpack the data structure

div0 = data.div0Date;
parentFolderPath = data.parentFolderPath;
refDir = data.refDir;
opDir = data.opDir;

    
% make output folder
if not(isfolder(append(opDir,'ActivityScan_outputs/Raster/')))
    mkdir(append(opDir,'ActivityScan_outputs/Raster/'));
end
if not(isfolder(append(opDir,'ActivityScan_outputs/AmplitudeMap/')))
    mkdir(append(opDir,'ActivityScan_outputs/AmplitudeMap/'));
end
if not(isfolder(append(opDir,'ActivityScan_outputs/FiringRateMap/')))
    mkdir(append(opDir,'ActivityScan_outputs/FiringRateMap/'));
end

% extract runID info from reference excel sheet
T = readtable(refDir);
run_ids = unique(T.(4));

% defines
% convert div 0 to date datatype
div0_date = datetime(div0, "InputFormat",'MM/dd/yyyy');
% create table elements
Run_ID = [];
DIV = [];
Time = [];
Well =[];
NeuronType={};
Chip_ID = {};
Mean_FiringRate = [];
Mean_SpikeAmplitude = [];
error_l = [];

%% iterate through ActivityScans
% get a list of all files in the folder with the desired file name pattern.
filePattern = fullfile(parentFolderPath, '**/ActivityScan/**/*.mxassay'); 
theFiles = dir(filePattern);
for k = 1 : length(theFiles)
    % Check for Cancel button press
    if d.CancelRequested
        break
    end

    % reset recording info
    scan_runID = nan;
    scan_chipID = nan;
    scan_meanFiringRate = nan;
    scan_meanSpikeAmplitude = nan;
    hd5Date = nan; 
    scan_div = nan;
    
    pathFileActivityScan = fullfile(theFiles(k).folder);
    % extract dir information
    fileDirParts = strsplit(pathFileActivityScan, filesep); % split dir into elements
    scan_runID = str2double(fileDirParts{end-0}); % extract runID
    scan_runID_text = fileDirParts{end-0};
    scan_chipID = fileDirParts{end-2}; % extract chipID
    % folderDate = datetime(fileDirParts{end-3},'InputFormat','yyMMdd','Format','MM-dd-yyyy'); % extract date and convert to date object
    
    if ismember(scan_runID,run_ids)
        fprintf(1, 'Now reading %s\n', pathFileActivityScan);
        fprintf(logFile, 'Now reading %s\n', pathFileActivityScan);
        % create fileManager object for the Activity Scan
            
            idx = T.Run_ == scan_runID;

        wellsIDs = T.Wells_Recorded(idx);

        if ismember(',', wellsIDs{1})
        wellsIDs = strsplit(wellsIDs{1}, ',');
        wellsIDs = cellfun(@str2double,wellsIDs);
        end

        
        neuronTypes = T.NeuronSource(idx);
        if ismember(',', neuronTypes{1})
        neuronTypes = strsplit(neuronTypes{1}, ',');

        end
        for z = 1:length(wellsIDs)
        wellID=wellsIDs(z);
        fprintf(logFile, 'Processing Well %d\n', wellID);
        neuronSourceType = neuronTypes(z);
        try
            %wellID = 1; % select which well to analyze
            %{
            lastwarn('','');
            diceyFunction(mxw.fileManager(pathFileActivityScan,wellID));
            [warnMsg,WarnID] = lastwarn();
            if isempty(warnID)
                noProblem();
            else
                error_l = [error_l string(scan_runID_text)];
            end
            %}
            activityScanData = mxw.fileManager(pathFileActivityScan,wellID);
        catch
            error_l = [error_l string(scan_runID_text)];
            continue
        end

        % get the startTime of the recordings
        hd5_time = activityScanData.fileObj.stopTime;
        try
            hd5Date = datetime(hd5_time,'InputFormat', 'yyyy-MM-dd HH:mm:ss');
        catch
            hd5Date = datetime(hd5_time,'InputFormat', 'dd-MMM-yyyy HH:mm:ss');
        end
        scan_div = fix(daysact(div0_date , hd5Date));

        % compute means
        % get the mean firing rate for each electrode
        meanFiringRate = mxw.activityMap.computeSpikeRate(activityScanData);
        % calculate the overall mean firing rate of the scan
        thrFiringRate = 0.1; % set a minimum spike rate threshold (Hz)
        scan_meanFiringRate = mean(meanFiringRate(meanFiringRate>thrFiringRate));
        % get th 90th percentile spike amplitude value for each electrode
        amplitude90perc = abs(mxw.activityMap.computeAmplitude90percentile(activityScanData));
        % calculate the overall mean spike amplitude of the scan
        thrAmp = 10;  % set a minimum spike amplitude threshold (uV)
        scan_meanSpikeAmplitude = mean(amplitude90perc(amplitude90perc>thrAmp));
    
        % append information to table elements
        Run_ID = [Run_ID scan_runID];
        DIV = [DIV scan_div];
        Well = [Well wellID];
        NeuronType{end+1} = neuronSourceType{1};
        Time = [Time hd5Date];
        Chip_ID{end+1}=scan_chipID;
        Mean_FiringRate = [Mean_FiringRate scan_meanFiringRate];
        Mean_SpikeAmplitude = [Mean_SpikeAmplitude scan_meanSpikeAmplitude];

        % plot amplitude and firing rate maps
        try
            % I. Raster Plots
            recNr = 3;
            % sampling frequency
            fsActivity = activityScanData.fileObj(recNr).samplingFreq;
            % get spike time stamps 
            tsActivity = double(activityScanData.fileObj(recNr).spikes.frameno - activityScanData.fileObj(recNr).firstFrameNum)/fsActivity;
            % channel list, where spike time stamps where detected
            chActivity = activityScanData.fileObj(recNr).spikes.channel;
            
            % plot raster
            figure('Color','w','visible','off');
            subplot(2,1,1)
            plot(tsActivity, chActivity,'.','Color','#135ba3','MarkerSize',2)
            box off 
            xlabel('Time [s]') 
            ylabel('Channel')
            title('Activity Scan Raster Plot')
            xmaxActivity = max(tsActivity);
            xlim([0 xmaxActivity])
            ylim([0 max(chActivity)])
            
            saveas(gcf,append(opDir,'ActivityScan_outputs/Raster/ActivityRaster',scan_runID_text,'_WellID_',num2str(wellID),'_',num2str(scan_chipID),'_DIV',num2str(scan_div),'_',strrep(neuronSourceType{1},' ',''),'.png'))
        catch
            fprintf('Unable to plot raster for run %s/n', scan_runID_text)
            fprintf(logFile,'Unable to plot raster for run %s/n', scan_runID_text);
        end
    
        % II. Spike Rate Activity Map and Distribution
        try
            % get the mean firing rate for each electrode
            meanFiringRate = mxw.activityMap.computeSpikeRate(activityScanData);
            
            % define maximum firing rate used in plots as 99th percentile of firing
            % rate values
            maxFiringRate = mxw.util.percentile(meanFiringRate(meanFiringRate~=0),99);
            
            % plot the list of mean firing rates as a map, given the electrode 
            % x and y coordinates in 'fileManagerObj.processedMap'
            figure('Color','w','visible','off');
            subplot(2,1,1);
            mxw.plot.activityMap(activityScanData, meanFiringRate, 'Ylabel', '[Hz]',...
                'CaxisLim', [0.1 max(meanFiringRate)/5],'Figure',false,'Title','Firing Rate Activity Map');
            % run the line above several times, experimenting with different 
            % [min max] range of the color gradient 'CaxisLim'
            
            % add scale bar 
            line([300 800],[2000+400 2000+400],'Color','k','LineWidth',4);
            axis off;
            text(340,2100+500,'0.5 mm','color','k');
            xlim([200 3750]);ylim([150 2500])
            
            % plot the distribution of firing rates across all of the electrodes
            subplot(2,1,2);
            thrFiringRate = 0.1; % set a minimum spike rate threshold (Hz)
            histogram(meanFiringRate(meanFiringRate>thrFiringRate),0:.1:ceil(maxFiringRate), ...
                'FaceColor','#135ba3', "EdgeColor",'#414042')
            xlim([thrFiringRate maxFiringRate])
            ylabel('Counts');xlabel('Firing Rate [Hz]');
            box off;
            legend(['Mean Firing Rate = ',num2str(mean(meanFiringRate(meanFiringRate>thrFiringRate)),'%.2f'),...
                ' Hz,  sd = ',num2str(std(meanFiringRate(meanFiringRate>thrFiringRate)),'%.2f')])
        
            saveas(gcf,append(opDir,'ActivityScan_outputs/FiringRateMap/FiringRateMap',scan_runID_text,'_WellID_',num2str(wellID),'_',num2str(scan_chipID),'_DIV',num2str(scan_div),'_',strrep(neuronSourceType{1},' ',''),'.png'))
        catch
            fprintf('Unable to plot Firing Rate Map for run s%/n',scan_runID_text)
            fprintf(logFile,'Unable to plot Firing Rate Map for run s%/n',scan_runID_text);
        end
        
        % III. Spike Amplitude Activity Map and Distribution
        try
            % get th 90th percentile spike amplitude value for each electrode
            amplitude90perc = abs(mxw.activityMap.computeAmplitude90percentile(activityScanData));
            
            % define maximum amplitude used in plots as 99th percentile of amplitude values
            maxAmp = mxw.util.percentile(amplitude90perc(amplitude90perc~=0),99);
            
            % plot the mean firing rate vector as a map, given the electrode 
            % x and y coordinates in 'fileManagerObj.processedMap'
            figure('Color','w','visible','off');
            subplot(2,1,1);
            mxw.plot.activityMap(activityScanData, amplitude90perc,'Ylabel', '[\muV]',...
                'CaxisLim', [10 maxAmp], 'Figure',false,'Title','Spike Amplitude Activity Map');
            % run the line above several times, experimenting with different 
            % [min max] range of the color gradient 'CaxisLim'
            
            % add scale bar 
            line([300 800],[2000+400 2000+400],'Color','k','LineWidth',4);
            axis off;
            text(340,2100+500,'0.5 mm','color','k');
            xlim([200 3750])
            ylim([150 2500])
            
            % plot the distribution of spike amplitudes across all of the electrodes
            subplot(2,1,2);
            thrAmp = 10;  % set a minimum spike amplitude threshold (uV)
            histogram(amplitude90perc(amplitude90perc>thrAmp),ceil(0:1:maxAmp), ...
                'FaceColor','#135ba3', "EdgeColor",'#414042')
            xlim([thrAmp maxAmp])
            ylabel('Counts');xlabel('Spike Amplitude [\muV]');
            box off;
            legend(['Mean Spike Amplitude = ',num2str(mean(amplitude90perc(amplitude90perc>thrAmp)),'%.2f'),...
                ' \muV,  sd = ',num2str(std(amplitude90perc(amplitude90perc>thrAmp)),'%.2f')])
        
            saveas(gcf,append(opDir,'ActivityScan_outputs/AmplitudeMap/AmplitudeMap',scan_runID_text,'_WellID_',num2str(wellID),'_',num2str(scan_chipID),'_DIV',num2str(scan_div),'_',strrep(neuronSourceType{1},' ',''),'.png'))
        catch
            fprintf('Unable to plot Amplitude Map for run %s/n', scan_runID_text)
            fprintf(logFile,'Unable to plot Amplitude Map for run %s/n', scan_runID_text);
        end
    end
end
if d.CancelRequested
    d.close()
    fprintf(logFile,'User Interruption');
    error("User interruption")
end
end
%% construct table
% convert row list to columns
Run_ID = Run_ID';
DIV = DIV';
Time = Time';
Well = Well';
NeuronType= NeuronType';
Chip_ID = Chip_ID';
Mean_FiringRate = Mean_FiringRate';
Mean_SpikeAmplitude = Mean_SpikeAmplitude';
% make table
T = table(Run_ID,DIV,Time,Chip_ID,Well,NeuronType,Mean_FiringRate,Mean_SpikeAmplitude);
T = sortrows(T,"Run_ID","ascend");
writetable(T, fullfile(opDir,'ActivityScan_outputs/Compiled_ActivityScan.csv'));

if ~isempty(error_l)
    error_str = strjoin(error_l,', ');
    fprintf('Unable to read file with runID: %s, file(s) skipped.\n',error_str);
    fprintf(logFile,'Unable to read file with runID: %s, file(s) skipped.\n',error_str);

end

fprintf('Activity Scan analysis successfully compiled.\n')
fprintf(logFile,'Activity Scan analysis successfully compiled.\n');
end