"""
Adapted Active Signature Method - aasm( x, step_size, f, iterations;..)
 
x_base: point at which the piecewise local model is build
f: abs-smooth function
lb_x, ub_x: lower and upper bound on x
alpha: step size of FW method
remaining arguments: function pointer
"""
###################################################################   

# get signature vector up to accuracy of myeps
"""
Signature vector at the point 'x' upto certain accuracy
"""
function signature_vec(s, z; myeps = 1.0e-12)         
  sigma_z=sign.(z)                                  
  
  for i=1:s
    if abs(z[i])<myeps
      sigma_z[i]=0;
    end
  end

  return sigma_z
end

# check optimality

###############################################################################
# Highs/GLPK uses L(x,z,lambda,mu) = f(x,z)-lambda^T eq_const - mu^T ineq_const
# this is different to the derivation in the ASM
#  => use -lambda in normal growth condition!!
###############################################################################

function check_normalGrowth(s, b, L, sigma_z, lambda, z; myeps=1.0e-12)   

  index = -1
  
  min_mu_val = 1.0/0.0
  
  for i=1:s
    mu = b[i]
    for j=1:s
      mu = mu-lambda[j]*L[i,j]                      
    end
    mu = mu-abs(lambda[i])
      
    if mu<0 && abs(sigma_z[i]==0) && abs(lambda[i])>=myeps
      if mu < min_mu_val
        index = i
        min_mu_val = mu
         @show sigma_z  
      end  
    end
  end
  return index
  
  end

###############################################################################

# adapted active signature method (AASM)
simplex_count = []

function aasm(x_base, alpha, f_eval, n, ub_x, lb_x, outer_iter; max_inner_iter=100, model="model", mps=false) 
   
# call the abs-linear form of f
   abs_normal_form = abs_linear(x_base,f_eval)
      
   s = abs_normal_form.num_switches
             
# to store asm information
   lambdas = []
   solutions = []
   
   iter = 1
   while iter <= max_inner_iter  
  
    o = Model(HiGHS.Optimizer)
    MOI.set(o, MOI.Silent(), true)

# variables: xz = (x,z)  => n+s variables
    @variable(o, xz[1:n+s])
    
    z = abs_normal_form.z
    
    set_start_value.(xz[1:n], x_base)
    set_start_value.(xz[n+1:end], z)
    
    sigma_z = signature_vec(s,z)
    
# define objective
    alf_a = abs_normal_form.Y
    alf_b = abs_normal_form.J 
    
    c = vcat(alf_a', alf_b' .* sigma_z)       
    @objective(o, Min, dot(c, xz))
  
################## define bound constraints ############################## 
# bounds on x from original problem - linear shift due to linearization
# here we compute \Delta v hence
# v \in C => lb_v <= v <= ub_v
# lb_v - x_base <= v - x_base <= ub_v-x_base
# alpha(lb_v - x_base) <= alpha(v - x_base) <= alpha(ub_v-x_base)
# alpha(lb_v - x_base) <= x_delta <= alpha(ub_v-x_base)
##########################################################################
    
    @constraint(o, xz[1:n] <= min.(alpha*(ub_x-x_base),1.0e30))          
    @constraint(o, xz[1:n] >= max.(alpha*(lb_x-x_base),-1.0e30))         
  
    @constraint(o, sigma_z .* xz[n+1:end] .>= 0) 
    
    Z = abs_normal_form.Z  
    L = abs_normal_form.L 
    
    A = [Z L.*sigma_z'-I]
    
    cz = abs_normal_form.cz
    
    c1 = @constraint(o, A*xz .== -cz)
    optimize!(o)
    
    myxz = [value(var) for var in all_variables(o)]    
    myxz = round.(myxz, digits=5)
    push!(solutions, myxz)
     
    x_delta = myxz[1:n]
    z = myxz[n+1:n+s]
# new abs linearization
    cy = abs_normal_form.cy 
    
    fpl_new = cy + alf_a*x_delta + alf_b*abs.(z)   

    if (fpl_new[1] > f_eval(x_base)[1] + 1.0e-12) || abs(fpl_new[1] - f_eval(x_base)[1]) < 1.0e-12
    
         iter+=1	

         gap = [0.0]  #fpl_new = f_eval(x_base)
    
       return x_delta, gap, solutions, lambdas, iter
		
    end

    mylambda = round.(dual.(c1), digits=3)
    push!(lambdas, mylambda)
    
# dual-gap for abs-smooth case

    gap = (f_eval(x_base) .- fpl_new)/alpha    

# local optimality criterion
    index_mu = check_normalGrowth(s, alf_b, L, sigma_z, mylambda, z) 
    
    if index_mu > -1
# current point not optimal, change polyhedron 
      sigma_z[index_mu]=-mylambda[index_mu]/abs(mylambda[index_mu]);      
       
    else
# local minimizer reached     
      return x_delta, gap, solutions, lambdas, iter
    end
    
#    iter = iter+1
  end

  return x_delta, gap, solutions, lambdas, iter 
end

