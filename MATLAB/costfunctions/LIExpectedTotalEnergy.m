%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% LIExpectedTotalEnergy
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Linear approximation of the line integral which gives the total
% energy consumed over a path (both motion and communication). We assume
% a linear interpolation of power between two  waypoints.
%
% Inputs:
% path - array of path waypoints. Path(i) = [xi, yi].
% cawo - channle analyzer with observations object
% qp - quality of service parameters and settings
% mp - motion parameters
% delta - weighting parameter for motion energy. If not provided, defaults
%           to 1 (equal weight with communication energy)
%
% Outputs:
% double energy_J - approximate energy consumed over path in Joules

function energy_J = LIExpectedTotalEnergy(path, cawo, qos, mp, delta)
    if nargin < 5
       delta = 1; 
    end
    
    v_const = mp.VConst;
    
    energy_J = 0;
    req_comm_power_a = qos.reqTXPower(cawo.posteriorExpecteddB(path(1,:)));
    for i=2:length(path)
        dist = norm(path(i-1,:) - path(i,:));
        req_comm_power_b = qos.reqTXPower(cawo.posteriorExpecteddB(path(i,:)));

        comm_energy = (dist/v_const)*(req_comm_power_a + req_comm_power_b)/2;
        energy_J = energy_J + delta*mp.motionEnergy(dist) + comm_energy;
        req_comm_power_a = req_comm_power_b;
    end
end
