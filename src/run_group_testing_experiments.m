%% Boolean Compressed Sensing — Group Testing Experiments
clear;
close all;
clc;

%% Project paths
scriptDir = fileparts(mfilename('fullpath'));

if isempty(scriptDir)
    scriptDir = pwd;
end

repoRoot = fullfile(scriptDir, '..');
dataDir = fullfile(repoRoot, 'data');
figuresDir = fullfile(repoRoot, 'figures');
algorithmsDir = fullfile(scriptDir, 'algorithms');

addpath(algorithmsDir);

if ~exist(figuresDir, 'dir')
    mkdir(figuresDir);
end

%% Select algorithm
% Options:
%   'comp'
%   'dd'
%   'mp'
%   'nnlasso'

algorithmName = 'dd';

switch lower(algorithmName)
    case 'comp'
        algorithmLabel = 'COMP';
        figurePrefix = 'comp';

    case 'dd'
        algorithmLabel = 'DD';
        figurePrefix = 'dd';

    case 'mp'
        algorithmLabel = 'MP';
        figurePrefix = 'mp';

    case 'nnlasso'
        algorithmLabel = 'Non-negative LASSO';
        figurePrefix = 'nnlasso';

    otherwise
        error('Unknown algorithm name: %s', algorithmName);
end

%% Initialization
p_values = 0.02:0.02:0.16;     % Pooling probabilities from 2% to 16%
M_values = 20:20:300;          % Number of measurements from 20 to 300
epsilon = 0.01;                % Stopping criterion for Matching Pursuit
lambda = 0.01;                 % Regularization parameter for non-negative LASSO

%% Load dataset
dataPath = fullfile(dataDir, 'group_testing_samples.mat');

if ~isfile(dataPath)
    error('Dataset not found at: %s', dataPath);
end

data = load(dataPath);

if ~isfield(data, 'x')
    error('The MAT file must contain a variable named x.');
end

x_samples = data.x;
sample_size = size(x_samples, 1);

% Uncomment this line for a faster test run
% sample_size = 100;

%% Storage arrays
num_p = length(p_values);
num_M = length(M_values);

hamming_distances = zeros(num_p, num_M, sample_size);
computing_times = zeros(num_p, num_M, sample_size);
false_positives = zeros(num_p, num_M, sample_size);
false_negatives = zeros(num_p, num_M, sample_size);

%% Run experiments
for sample_idx = 1:sample_size
    x_true = double(x_samples(sample_idx, :)');

    fprintf('Processing sample %d / %d\n', sample_idx, sample_size);

    for p_idx = 1:num_p
        for M_idx = 1:num_M

            p = p_values(p_idx);
            M = M_values(M_idx);

            %% Generate Bernoulli pooling matrix
            A_logical = rand(M, length(x_true)) < p;
            A = double(A_logical);

            %% Generate Boolean group testing measurements
            y = double(any(A_logical & (x_true' == 1), 2));

            %% Decode
            tic;

            switch lower(algorithmName)
                case 'comp'
                    x_estimate = comp_decoder(A, y);

                case 'dd'
                    x_estimate = dd_decoder(A, y);

                case 'mp'
                    x_estimate = boolean_matching_pursuit(A, y, epsilon);
                    x_estimate = double(x_estimate >= 1);

                case 'nnlasso'
                    x_score = nonnegative_lasso_decoder(A, y, lambda);
                    x_estimate = double(x_score >= 0.5);
            end

            computing_time = toc;

            x_estimate = double(x_estimate(:) >= 1);

            %% Evaluation metrics
            TP = sum((x_true == 1) & (x_estimate == 1));
            TN = sum((x_true == 0) & (x_estimate == 0));
            FP = sum((x_true == 0) & (x_estimate == 1));
            FN = sum((x_true == 1) & (x_estimate == 0));

            false_positives(p_idx, M_idx, sample_idx) = FP / max(FP + TN, 1);
            false_negatives(p_idx, M_idx, sample_idx) = FN / max(FN + TP, 1);

            computing_times(p_idx, M_idx, sample_idx) = computing_time;
            hamming_distances(p_idx, M_idx, sample_idx) = sum(abs(x_true - x_estimate));
        end
    end
end

%% Compute averages
mean_hamming_distances = mean(hamming_distances, 3);
mean_computing_times = mean(computing_times, 3);
average_fpr = mean(false_positives, 3);
average_fnr = mean(false_negatives, 3);

colors = jet(num_p);

%% Plot 1: Hamming distance
figure;
hold on;

for p_idx = 1:num_p
    plot(M_values, mean_hamming_distances(p_idx, :), ...
        'Color', colors(p_idx, :), ...
        'LineWidth', 1.2);
end

title(sprintf('Hamming Distance vs. Number of Measurements (%s)', algorithmLabel));
xlabel('Number of Measurements (M)');
ylabel('Mean Hamming Distance');
legend(arrayfun(@(p) sprintf('p = %.2f', p), p_values, 'UniformOutput', false), ...
    'Location', 'northeast');
xlim([M_values(1), M_values(end)]);
grid on;
hold off;

saveas(gcf, fullfile(figuresDir, sprintf('%s_hamming_distance.png', figurePrefix)));

%% Plot 2: Hamming distance surface
figure;
surf(M_values, p_values, mean_hamming_distances);
xlabel('Number of Measurements (M)');
ylabel('Pooling Probability (p)');
zlabel('Mean Hamming Distance');
title(sprintf('Hamming Distance for Various p and M (%s)', algorithmLabel));
view(37.5, 20);
grid on;

saveas(gcf, fullfile(figuresDir, sprintf('%s_hamming_distance_surface.png', figurePrefix)));

%% Plot 3: Computing time
figure;
hold on;

for p_idx = 1:num_p
    plot(M_values, mean_computing_times(p_idx, :), ...
        'Color', colors(p_idx, :), ...
        'LineWidth', 1.2);
end

title(sprintf('Computing Time vs. Number of Measurements (%s)', algorithmLabel));
xlabel('Number of Measurements (M)');
ylabel('Mean Computing Time');
legend(arrayfun(@(p) sprintf('p = %.2f', p), p_values, 'UniformOutput', false), ...
    'Location', 'northwest');
xlim([M_values(1), M_values(end)]);
grid on;
hold off;

saveas(gcf, fullfile(figuresDir, sprintf('%s_runtime.png', figurePrefix)));

%% Plot 4: Computing time surface
figure;
surf(M_values, p_values, mean_computing_times);
xlabel('Number of Measurements (M)');
ylabel('Pooling Probability (p)');
zlabel('Mean Computing Time');
title(sprintf('Computing Time for Various p and M (%s)', algorithmLabel));
view(330, 20);
grid on;

saveas(gcf, fullfile(figuresDir, sprintf('%s_runtime_surface.png', figurePrefix)));

%% Plot 5: False negative rate
figure;
hold on;

for p_idx = 1:num_p
    plot(M_values, average_fnr(p_idx, :), ...
        'Color', colors(p_idx, :), ...
        'LineWidth', 1.2);
end

title(sprintf('False Negative Rate vs. Number of Measurements (%s)', algorithmLabel));
xlabel('Number of Measurements (M)');
ylabel('Mean False Negative Rate');
legend(arrayfun(@(p) sprintf('p = %.2f', p), p_values, 'UniformOutput', false), ...
    'Location', 'northeast');
xlim([M_values(1), M_values(end)]);
grid on;
hold off;

saveas(gcf, fullfile(figuresDir, sprintf('%s_false_negative_rate.png', figurePrefix)));

%% Plot 6: False positive rate
figure;
hold on;

for p_idx = 1:num_p
    plot(M_values, average_fpr(p_idx, :), ...
        'Color', colors(p_idx, :), ...
        'LineWidth', 1.2);
end

title(sprintf('False Positive Rate vs. Number of Measurements (%s)', algorithmLabel));
xlabel('Number of Measurements (M)');
ylabel('Mean False Positive Rate');
legend(arrayfun(@(p) sprintf('p = %.2f', p), p_values, 'UniformOutput', false), ...
    'Location', 'northeast');
xlim([M_values(1), M_values(end)]);
grid on;
hold off;

saveas(gcf, fullfile(figuresDir, sprintf('%s_false_positive_rate.png', figurePrefix)));

%% Plot 7: False positive rate surface
figure;
surf(M_values, p_values, average_fpr);
xlabel('Number of Measurements (M)');
ylabel('Pooling Probability (p)');
zlabel('Mean False Positive Rate');
title(sprintf('False Positive Rate for Various p and M (%s)', algorithmLabel));
view(37.5, 20);
grid on;

saveas(gcf, fullfile(figuresDir, sprintf('%s_false_positive_rate_surface.png', figurePrefix)));

%% Plot 8: False negative rate surface
figure;
surf(M_values, p_values, average_fnr);
xlabel('Number of Measurements (M)');
ylabel('Pooling Probability (p)');
zlabel('Mean False Negative Rate');
title(sprintf('False Negative Rate for Various p and M (%s)', algorithmLabel));
view(37.5, 20);
grid on;

saveas(gcf, fullfile(figuresDir, sprintf('%s_false_negative_rate_surface.png', figurePrefix)));

%% Save numerical results
resultsFile = fullfile(figuresDir, sprintf('%s_results.mat', figurePrefix));

save(resultsFile, ...
    'algorithmName', ...
    'p_values', ...
    'M_values', ...
    'mean_hamming_distances', ...
    'mean_computing_times', ...
    'average_fpr', ...
    'average_fnr');

fprintf('\nFinished running %s.\n', algorithmLabel);
fprintf('Figures and results saved in: %s\n', figuresDir);