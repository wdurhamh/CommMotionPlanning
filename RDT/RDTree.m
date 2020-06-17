classdef RDTree < handle
    
    properties
        %doRewire - if true, will rewire, that is, will run RRT* rather
        %than RRT
        doRewire;
        
        %steerRad - maximum distance the tree can grow at a time, that is
        %maximum distance between p_nearest and p_new
        steerRad;
        
        %BSF = TreeNode. Path from BSF to root traces the best path found
        %so far
        BSF;
        
        %treeNodes = [root, n1, n2, ....], the list of nodes in the tree,
        %in order in which they are added.
        treeNodes;
        
        %see "Sampling-based Algorithms for Optimal Motion Planning",
        %s. Karaman, E. Frazzoli, 2011 
        gamma;
        
        %
        solCosts;
        
        %neighborBoxes - data structure presented in "Minimising 
        %computational complexity of the RRT algorithm a practical
        %approach" M Sventrup et. al, 2011
        %neighborBoxes;
        
        %
        isContinuous;
        
        theta;
    end
    
    methods
        function this = RDTree(do_rewire, steer_rad)
           this.doRewire = do_rewire;
           this.steerRad = steer_rad;
           
           %create a placeholder BSF with infinite cost
            this.BSF = TreeNode([-Inf,-Inf]);
            this.BSF.distToHere = Inf;
            
        end
        
        %setup asspects of the tree before beginning the algorithm
        function initialize(this, gamma, root_pos, is_continuous, theta)
            if nargin == 4
                theta = 1;
            end
            
            this.theta = theta;
            this.gamma = gamma;
            
            root = TreeNode(root_pos);
            root.isRoot = 1;
            root.distToHere = 0;
            this.treeNodes = [root];
            
            if nargin == 4
                this.isContinuous = is_continuous;
            else
                this.isContinuous = 0;
            end
            
        end
        
        function executeIteration(this, x_rand, pppi)
            
            [success, new_node] = this.tryAddNode(x_rand, pppi);
            
            %check if the new_node has given us a new BSF
            if success && pppi.nodeInDestGrid(new_node) && this.BSF.distToHere > new_node.distToHere 
                this.BSF = new_node;
            end
        end
        
        function [success, n_new] = tryAddNode(this, x_rand, pppi)
            success = 0;
            %initialize dummy new node
            n_new = TreeNode([Inf, Inf]);
            [nearest, min_dist] = this.nearest(x_rand);
            %check to see if we already have this node added to the tree
            %should be able to just check if zero again, but let's validate
            if  min_dist > 1/2 
                path = this.steer(x_rand, nearest);
                %check if the path is collision free, trimming if necessary
                viable_path = pppi.collisionFree(path);
                
                if min(size(viable_path)) > 1 % more than one point in path
                    success = 1;
                    n_new = this.addNode(nearest, viable_path, this.doRewire, pppi);
                end
            else
                %handle the case where we resample an already sampled
                %point. Need to rewire. Look into literature
                this.rewire(nearest,pppi)
            end
        end
         
        function recordBSFCost(this, time)
            if this.BSF.distToHere ~= Inf
                this.solCosts = [this.solCosts; time, this.BSF.distToHere]; 
            end
        end
    end
    
    methods (Access = private)

         %addNode
         function n_new = addNode(this, nearest, path, do_rewire, pppi)
            new_node = TreeNode(path(end,:));
            dist = pppi.pathCost(new_node, nearest, path);
            new_node.setParent(nearest, dist, path); 
            this.treeNodes = [this.treeNodes, new_node];
            
            n_new = new_node;
            if do_rewire
                this.rewire(n_new, pppi);
            end
         end
        
        %rewire
        % TODO - rewire also includes finding shortest path (not just
        % closest TO the new node)
        % TODO - implement with balanced box decomposition
        %can be implemented in O(log n) time using Balanced Box Decomposition
        %currently is O(n) (brute force)
        function rewire(this, current, pppi)
            %See Karaman & Frazzoli, 2011
            cardV = length(this.treeNodes);
            radius = min(this.steerRad, this.gamma*sqrt(log(cardV)/cardV));
            
            x_current = current.wrkspcpos;
            %the last node in the list will be the one we just added, i.e.
            %current, so don't bother checking that one
            max_i = length(this.treeNodes)-1;
            for i = 1:max_i
               this_vertex = this.treeNodes(i);
               x_this = this_vertex.wrkspcpos;
               %use Eucliden distance for the neighborhood radius check
               dist = norm(x_this - x_current);
               
               if dist <= radius
                   path = this.getSLPath(x_current, x_this);
                   cost = this.theta*pppi.pathCost(current, this_vertex, path);

                    if (this_vertex.distToHere > (current.distToHere + cost)) && (this_vertex ~= current)
                        if cost == 0
                              %somehow we have a duplicate node, which
                              %shouldn't happen
                              1;
                        end
                        
                        %check to make sure there's nothing obstructing
                        viable_path = pppi.collisionFree(path);
                        
                        if norm(size(viable_path) - size(path)) == 0
                           %do the actual rewiring
                           %remove this child from it's parent
                           old_parent = this_vertex.parent;
                           old_parent.removeChild(this_vertex);
                           
                           %now add the new parent
                           this_vertex.setParent(current, cost, path);
                        end
                    end
               end
            end
        end
         
         
         function path = steer(this, x_rand, v_nearest)

            start = v_nearest.wrkspcpos;
            diff = x_rand - start;
            %don't extend beyond the newly sampled point
            if norm(diff) > this.steerRad
            
                %find the direction
                theta = atan2(diff(2), diff(1));

                new_diff = [this.steerRad*cos(theta), this.steerRad*sin(theta)];
                if ~this.isContinuous
                    new_diff = this.roundSteerPoint(new_diff);
                end
                

                new = start + new_diff;
            else
               new =  x_rand;
            end
            
           path = this.getSLPath(start, new);
            
        end

        % TODO - implement with balanced box decomposition (space O(n), 
        % time O(log(n))) or boxed (space = grid_x_dim * grid_y_dim, time O(1))
        %currently is O(n) (brute force)
        function [nearest, min_dist] = nearest(this, x_rand)
            root = this.treeNodes(1);
            min_dist = norm(root.getPos() - x_rand);
            nearest = root;
            for i = 2:length(this.treeNodes)
               dist = norm(this.treeNodes(i).getPos() - x_rand);
               if dist < min_dist
                  min_dist = dist;
                  nearest = this.treeNodes(i);
               end
            end
        end
        
        function rounded = roundSteerPoint(this, raw_steer_pt)
            rounded = round(raw_steer_pt);
            %ensure we're not beyond the steer radius
            if norm(rounded) > this.steerRad
                index1 = randi(2,1);

                if rounded(index1) > raw_steer_pt(index1)
                   rounded(index1) = sign(rounded(index1))*(abs(rounded(index1)) - 1);
                end

                index2 = mod(index1 + 1, 2) + 1;
                if norm(rounded) < this.steerRad && rounded(index2) > raw_steer_pt(index2)
                    rounded(index2) = sign(rounded(index2))*(abs(rounded(index2)) - 1);
                end
            end
        end
        
        function path = getSLPath(this, start, dest)
             if this.isContinuous
                path = [start; dest];
            else
                %also calculate intermediate path
                path = RDTree.getApproxGridSLPath(start, dest);
            end
        end
         
    end
    
    methods(Access = private, Static = true)
        
     
         function path = getApproxGridSLPath(start, dest)
            dist = start - dest;
            dist_abs = abs(dist);
            mabs = dist_abs(2)/dist_abs(1);
            min_path_length = sum(dist_abs) + 1;
            if(min_path_length < 2)
               1; 
            end
            
            path = zeros([min_path_length, 2]);
            path(1,:) = start;
            path(end,:) = dest;
            for i = 2:min_path_length - 1
                %just straight up /down
                if mabs == Inf
                   path(i,:) = path(i-1,:) + [0,-1*sign(dist(2))];
                elseif mabs == 0
                    %just straight left or right
                    path(i,:) = path(i-1,:) + [-1*sign(dist(1)), 0];
                else
                    %get slope from v_nearest to previous point.
                    prev_delta = abs(path(1,:) - path(i-1, :));
                    prev_slope = prev_delta(2)/prev_delta(1);
                    if prev_slope <= mabs
                       %need more rise
                       path(i,:) = path(i-1,:) + [0, -1*sign(dist(2))];
                    else
                        %otherwise, needs to run more
                        path(i,:) = path(i-1,:) + [-1*sign(dist(1)), 0];
                    end
                end
            end
        end
    end
end
