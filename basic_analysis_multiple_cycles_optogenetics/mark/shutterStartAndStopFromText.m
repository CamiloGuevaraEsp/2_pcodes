function [shutteredStartAndStopTimes, seconds_baseline] = shutterStartAndStopFromText(voltTextString) %,stackStartAndEnd);

seconds_baseline =29.99;
numPulses = 60;
% shutteredStartAndStopTimes = zeros(numPulses,2)+seconds_baseline;

if(strcmp(voltTextString,'200ms 1 Hz 30s baseline')), %||strcmp(voltTextString,'200ms 1 Hz 120s baseline')),
    pulseDur = 0.22;
    interPulseInterval = 0.780;
elseif(strcmp(voltTextString,'5 min baseline 2ms pulse 30 Hz x 30')),
    pulseDur = 0.002;
    interPulseInterval = 0.0331;
    seconds_baseline = 300;
    numPulses = 30;
elseif(strcmp(voltTextString,'5 min baseline 2ms pulse 30 Hz x 30 every 5s')),
    numPulses = 6;
    seconds_baseline = 300;
    pulseDur = 1;
    interPulseInterval = 4;
%     pulseDur = 0.002;
%     interPulseInterval = 0.331;
%     seconds_baseline = 300;
%     numPulses = 30;
elseif(strcmp(voltTextString,'5 min baseline 2ms pulse 1 Hz x 30')), 
    pulseDur = 0.002;
    interPulseInterval = 0.998;
    seconds_baseline = 300;
    numPulses = 30;
elseif(strcmp(voltTextString,'2.5 min baseline 10 ms pulse')), 
    pulseDur = 0.01;
    interPulseInterval = 0.99;
    seconds_baseline = 150;
    numPulses = 1;
elseif(strcmp(voltTextString,'2.5 min baseline 10 ms pulse mark')), 
    pulseDur = 0.01;
    interPulseInterval = 0.99;
    seconds_baseline = 150;
    numPulses = 1;
elseif(strcmp(voltTextString,'2.5 min baseline 100 ms pulse')), 
    pulseDur = 0.1;
    interPulseInterval = 0.9;
    seconds_baseline = 150;
    numPulses = 1;
elseif(strcmp(voltTextString,'2.5 min baseline 100 ms pulse mark')), 
    pulseDur = 0.1;
    interPulseInterval = 0.9;
    seconds_baseline = 150;
    numPulses = 1;
elseif(strcmp(voltTextString,'2.5 min baseline 2ms x 30 puses at 30 Hz')), 
    pulseDur = 0.002;
    interPulseInterval = 0.03133;
    seconds_baseline = 150;
    numPulses = 30;
elseif(strcmp(voltTextString,'2.5 min baseline 2 ms pulse 30 Hz 30 pulses mark')), 
    pulseDur = 0.002;
    interPulseInterval = 0.03133;
    seconds_baseline = 150;
    numPulses = 30;
elseif(strcmp(voltTextString,'50ms 1 Hz 30s baseline')),
    pulseDur = 0.07;
    interPulseInterval = 0.925;
elseif(strcmp(voltTextString,'100ms 1 Hz 30s baseline')),
    pulseDur = 0.12;
    interPulseInterval = 0.88;
elseif(strcmp(voltTextString,'45s stim 100ms 1 Hz pulse 30s baseline')),
        pulseDur = 0.12;
    interPulseInterval = 0.88;
%     numPulses = 45;
elseif(strcmp(voltTextString,'100ms 1 Hz 120s baseline')),
    seconds_baseline = 119.99;
        pulseDur = 0.12;
    interPulseInterval = 0.88;
elseif(strcmp(voltTextString,'60s stim 30s baseline')),
    pulseDur = 0.07; %5 ms pulses. This is a 50 ms placeholder since I don't actually have the shutter durations recorded for this one.
    interPulseInterval = 0.0925;
elseif(strcmp(voltTextString,'200ms 1 Hz 120s baseline'))
    seconds_baseline=119.99;
    pulseDur = 0.22;
    interPulseInterval = 0.780;
elseif(strcmp(voltTextString,'1sOn1sOff120s baseline'))
    numPulses = 30;
    seconds_baseline = 119.99;
    pulseDur = 1.22;
    interPulseInterval = 0.780;
elseif(strcmp(voltTextString,'30s 1 Hz 200 ms stimulus pulse')),
    seconds_baseline=119.99;
    pulseDur = 0.22;
    interPulseInterval = 0.780;
    numPulses = 30;
% elseif(~isempty(strfind(voltTextString,'300s baseline'))),
%     seconds_baseline = 300;
%     if(~isempty(strfind(voltTextString,'2ms pulses'))),
%         pulseDur = 0.001;
%     end;
%     if(~isempty(strfind(voltTextString,'30-2ms'))),
%         interPulseInterval = 0.029;
%         numPulses = 30;
% %         pulseDur = 0.1;
%     end;
% elseif(~isempty(strfind(voltTextString,'180s baseline'))),
%     %'30-5ms 1 Hz pulses 180s baseline'
%     seconds_baseline = 180;
%     pulseDur = 0.001;
%     if(~isempty(strfind(voltTextString,'30-5ms'))),
%         interPulseInterval = 0.999;
%         numPulses = 30;
% %         pulseDur = 0.1;
%     end;
    
else,
    display(['Could not find a match for: ' voltTextString]);
end;

%Second row of the shutteredStartAndStopTimes array would be
%pulseDur+interPulseInterval after the first one.


if numPulses  == 1
    
    shutteredStartAndStopTimes(:,1) = seconds_baseline;
    shutteredStartAndStopTimes(:,2) =  seconds_baseline + pulseDur;
    
else
    
    
    pulseCycle = pulseDur+interPulseInterval;
    pulseStartTimes = [0:(numPulses-1)]*pulseCycle+seconds_baseline;
    shutteredStartAndStopTimes = zeros(numPulses,2);
% display(size(pulseStartTimes));
% display(size(
    shutteredStartAndStopTimes(:,1) = shutteredStartAndStopTimes(:,1)+pulseStartTimes';
    shutteredStartAndStopTimes(:,2) = shutteredStartAndStopTimes(:,1)+pulseDur;
end

% display(numel(pulseStartTimes));

