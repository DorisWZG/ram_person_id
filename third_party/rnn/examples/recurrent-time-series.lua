-- Multi-variate time-series example 

require 'rnn'

cmd = torch.CmdLine()
cmd:text()
cmd:text('Train a multivariate time-series model using RNN')
cmd:option('--rho', 5, 'maximum number of time steps for back-propagate through time (BPTT)')
cmd:option('--multiSize', 6, 'number of random variables as input and output')
cmd:option('--hiddenSize', 10, 'number of hidden units used at output of the recurrent layer')
cmd:option('--dataSize', 100, 'total number of time-steps in dataset')
cmd:option('--batchSize', 8, 'number of training samples per batch')
cmd:option('--nIterations', 1000, 'max number of training iterations')
cmd:option('--learningRate', 0.001, 'learning rate')
cmd:text()
local opt = cmd:parse(arg or {})

-- For simplicity, the multi-variate dataset in this example is independently distributed.
-- Toy dataset (task is to predict next vector, given previous vectors) following the normal distribution .
-- Generated by sampling a separate normal distribution for each random variable.
-- note: vX is used as both input X and output Y to save memory
local function evalPDF(vMean, vSigma, vX)
    for i = 1, vMean:size(1) do
        local b = (vX[i] - vMean[i]) / vSigma[i]
        vX[i] = math.exp(-b * b / 2) / (vSigma[i] * math.sqrt(2 * math.pi))
    end
    return vX
end

assert(opt.multiSize > 1, "Multi-variate time-series")

vBias = torch.randn(opt.multiSize)
vMean = torch.Tensor(opt.multiSize):fill(5)
vSigma = torch.linspace(1, opt.multiSize, opt.multiSize)
sequence = torch.Tensor(opt.dataSize, opt.multiSize)

j = 0
for i = 1, opt.dataSize do
    sequence[{ i, {} }]:fill(j)
    evalPDF(vMean, vSigma, sequence[{ i, {} }])
    sequence[{ i, {} }]:add(vBias)
    j = j + 1
    if j > 10 then j = 0 end
end
print('Sequence:'); print(sequence)

-- batch mode

offsets = torch.LongTensor(opt.batchSize):random(1, opt.dataSize)

-- RNN
r = nn.Recurrent(opt.hiddenSize, -- size of output
    nn.Linear(opt.multiSize, opt.hiddenSize), -- input layer
    nn.Linear(opt.hiddenSize, opt.hiddenSize), -- recurrent layer
    nn.Sigmoid(), -- transfer function
    opt.rho)

rnn = nn.Sequential():add(r):add(nn.Linear(opt.hiddenSize, opt.multiSize))

criterion = nn.MSECriterion()

-- use Sequencer for better data handling
rnn = nn.Sequencer(rnn)

criterion = nn.SequencerCriterion(criterion)
print("Model :")
print(rnn)

-- train rnn model
minErr = opt.multiSize -- report min error
minK = 0
avgErrs = torch.Tensor(opt.nIterations):fill(0)
for k = 1, opt.nIterations do

    -- 1. create a sequence of rho time-steps

    local inputs, targets = {}, {}
    for step = 1, opt.rho do
        -- batch of inputs
        inputs[step] = inputs[step] or sequence.new()
        inputs[step]:index(sequence, 1, offsets)
        -- batch of targets
        offsets:add(1) -- increase indices by 1
        offsets[offsets:gt(opt.dataSize)] = 1
        targets[step] = targets[step] or sequence.new()
        targets[step]:index(sequence, 1, offsets)
    end

    -- 2. forward sequence through rnn

    local outputs = rnn:forward(inputs)
    local err = criterion:forward(outputs, targets)

    -- report errors

    print('Iter: ' .. k .. '   Err: ' .. err)
    avgErrs[k] = err
    if avgErrs[k] < minErr then
        minErr = avgErrs[k]
        minK = k
    end

    -- 3. backward sequence through rnn (i.e. backprop through time)

    rnn:zeroGradParameters()

    local gradOutputs = criterion:backward(outputs, targets)
    local gradInputs = rnn:backward(inputs, gradOutputs)

    -- 4. updates parameters

    rnn:updateParameters(opt.learningRate)
end

print('min err: ' .. minErr .. ' on iteration ' .. minK)
