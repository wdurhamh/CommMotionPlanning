classdef RDTSolver < handle
    %RDTSolver - can solve instances of PathPlanningProblem using Randomly
    %Exploring Random Trees, including RRT and RRT*. Flexible enough to
    %handle some variants 
    
    properties (Access = private)
        %sampler - sampling module to use
        sampler;
        
        %stopCriteria - function handle. Function determines whether or not
        %we should stop. Arguments are elapsed time, iteration number, and cost
        %of best solution so far
        stopCriteria;
        
        %rdTree - The tree being built out
        rdTree;
        
    end
    
    methods (Access = public)
        function this = RDTSolver(sampler, stop_criteria, do_rewire, steer_rad)
           this.sampler = sampler;
           this.stopCriteria = stop_criteria;
            
            this.rdTree = RDTree(do_rewire, steer_rad);
            
        end
        
        function solve(this, pppi)
            tic;
            this.initializeTree(pppi);
            if ~this.startInDest(pppi)
                this.sampler.setParams(pppi);

                iteration_count = 0;
                elapsed_time = toc;
                series_delta = 0.2;
                time_for_next_recording = series_delta;

                while ~this.stopCriteria.stop(elapsed_time , iteration_count, this.getBSF())
                    x_rand = this.sampler.sample(iteration_count, pppi, this.minCostSoFar());

                    this.rdTree.executeIteration(x_rand, pppi);

                    iteration_count = iteration_count + 1;
                    elapsed_time = toc;
                    if elapsed_time > time_for_next_recording
                        time_for_next_recording = time_for_next_recording + series_delta;
                       this.rdTree.recordBSFCost(elapsed_time); 
                    end
                end
            end
        end
        
        function root = getRoot(this)
           root = this.rdTree.treeNodes(1); 
        end
        
        function tail = getBSF(this)
            tail = this.rdTree.BSF;
        end
        
        function [costs, dists] = getBSFTimeSeries(this)
            costs = this.rdTree.solCosts;
            dists = this.rdTree.solDists;
        end
        
        function cost = minCostSoFar(this)
            cost = this.getBSF().distToHere;
        end
    end
    
    methods (Access = private)

        function initializeTree(this, pppi)
           
           %see Karaman & Frazzoli, 2011, page 29. Here, d=2 
           root_pos = pppi.getSource();
           region = pppi.getRegion();
           length = (region(1) - region(2));
           width = (region(3) - region(4));
           area = length*width;%total area will be >= area of X_free
           gamma =  sqrt(3*(area/2*pi));

           this.rdTree.initialize(gamma, root_pos, pppi.isContinuous());
        end
        
        function tf = startInDest(this, pppi)
            root_pos = pppi.getSource();
            tf = pppi.pointInGoalRegion(root_pos);
            if tf
                this.rdTree.BSF = this.rdTree.treeNodes(1);
            end
        end
    end
end

