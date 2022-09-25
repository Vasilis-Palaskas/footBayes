functions{
      real skellam_lpmf(int k, real lambda1, real lambda2) {
        real r = k;
        return -(lambda1 + lambda2) + (r/2) * log(lambda1/lambda2) +
          log(modified_bessel_first_kind(k, 2 * sqrt(lambda1 * lambda2)));
      }

       real zero_infl_skellam_lpmf(int k, real lambda1, real lambda2, real p) {
    // This way is the easiest and proposed by https://github.com/Torvaney/karlis-ntzoufras-reproduction.
    // However, within model block, we propose in a comment the alternative way that Stan proposes in their documentation for zero inflated models
      real base_prob;
      real prob;
      real log_prob;

      base_prob = exp(skellam_lpmf(k| lambda1,lambda2));

      if (k== 0)
        prob = p + (1 - p) * base_prob;
      else
        prob = (1 - p) * base_prob;

      log_prob = log(prob);

      return log_prob;
    }

}
    data{
      int N;
      int N_prev;
      int diff_y[N];
      int nteams;
      int team1[N];
      int team2[N];
      int team1_prev[N_prev];
      int team2_prev[N_prev];
      real ranking[nteams];

      // priors part
      int<lower=1,upper=4> prior_dist_num;    // 1 gaussian, 2 t, 3 cauchy, 4 laplace
      int<lower=1,upper=4> prior_dist_sd_num; // 1 gaussian, 2 t, 3 cauchy, 4 laplace

      real hyper_df;
      real hyper_location;

      real hyper_sd_df;
      real hyper_sd_location;
      real hyper_sd_scale;
    }
    parameters{
      vector[nteams] att_raw;
      vector[nteams] def_raw;
      real<lower=0> sigma_att;
      real<lower=0> sigma_def;
      real home;
      real gamma;
      real <lower=0,upper=1> prob_of_draws;// excessive probability of draws

    }
    transformed parameters{
      vector[nteams] att;
      vector[nteams] def;
      real theta[N,2];

      for (t in 1:nteams){
        att[t] = att_raw[t]-mean(att_raw);
        def[t] = def_raw[t]-mean(def_raw);
      }

      for (n in 1:N){
        theta[n,1] = exp(home+att[team1[n]]+def[team2[n]]+
                         (gamma/2)*(ranking[team1[n]]-ranking[team2[n]]));
        theta[n,2] = exp(att[team2[n]]+def[team1[n]]-
                         (gamma/2)*(ranking[team1[n]]-ranking[team2[n]]));
      }
    }
model{
      // log-priors for team-specific abilities
      for (t in 1:(nteams)){
        if (prior_dist_num == 1){
          target+= normal_lpdf(att_raw[t]|hyper_location, sigma_att);
          target+= normal_lpdf(def_raw[t]|hyper_location, sigma_def);
        }
        else if (prior_dist_num == 2){
          target+= student_t_lpdf(att_raw[t]|hyper_df, hyper_location, sigma_att);
          target+= student_t_lpdf(def_raw[t]|hyper_df, hyper_location, sigma_def);
        }
        else if (prior_dist_num == 3){
          target+= cauchy_lpdf(att_raw[t]|hyper_location, sigma_att);
          target+= cauchy_lpdf(def_raw[t]|hyper_location, sigma_def);
        }
        else if (prior_dist_num == 4){
          target+= double_exponential_lpdf(att_raw[t]|hyper_location, sigma_att);
          target+= double_exponential_lpdf(def_raw[t]|hyper_location, sigma_def);
        }
      }


      // log-hyperpriors for sd parameters
      if (prior_dist_sd_num == 1 ){
        target+=normal_lpdf(sigma_att|hyper_sd_location, hyper_sd_scale);
        target+=normal_lpdf(sigma_def|hyper_sd_location, hyper_sd_scale);
      }
      else if (prior_dist_sd_num == 2){
        target+=student_t_lpdf(sigma_att|hyper_sd_df, hyper_sd_location, hyper_sd_scale);
        target+=student_t_lpdf(sigma_def|hyper_sd_df, hyper_sd_location, hyper_sd_scale);
      }
      else if (prior_dist_sd_num == 3){
        target+=cauchy_lpdf(sigma_att|hyper_sd_location, hyper_sd_scale);
        target+=cauchy_lpdf(sigma_def|hyper_sd_location, hyper_sd_scale);
      }
      else if (prior_dist_sd_num == 4){
        target+=double_exponential_lpdf(sigma_att|hyper_sd_location, hyper_sd_scale);
        target+=double_exponential_lpdf(sigma_def|hyper_sd_location, hyper_sd_scale);
      }

      // log-priors fixed effects
      target+=normal_lpdf(home|0,5);
      target+=normal_lpdf(gamma|0,1);
      target+=uniform_lpdf(prob_of_draws|0,1);


      // likelihood
      for (n in 1:N){
        target+=zero_infl_skellam_lpmf(diff_y[n]| theta[n,1],theta[n,2],
        prob_of_draws);
      }
}

generated quantities{
      int y_rep[N,2];
      int diff_y_rep[N];
      vector[N] log_lik;
      int y_prev[N_prev,2];
      vector[2] theta_prev[N_prev];
      int diff_y_prev[N_prev];

      //in-sample replications
      for (n in 1:N){
        y_rep[n,1] = poisson_rng(theta[n,1]);
        y_rep[n,2] = poisson_rng(theta[n,2]);
        diff_y_rep[n] = y_rep[n,1] - y_rep[n,2];
        log_lik[n] =zero_infl_skellam_lpmf(diff_y[n]| theta[n,1],theta[n,2],
        prob_of_draws);
      }
      //out-of-sample predictions
      for (n in 1:N_prev){
        theta_prev[n,1] = exp(home+att[team1_prev[n]]+
                                def[team2_prev[n]]+
                         (gamma/2)*(ranking[team1_prev[n]]-ranking[team2_prev[n]]));
        theta_prev[n,2] = exp(att[team2_prev[n]]+
                                def[team1_prev[n]]-
                         (gamma/2)*(ranking[team1_prev[n]]-ranking[team2_prev[n]]));
        y_prev[n,1] = poisson_rng(theta_prev[n,1]);
        y_prev[n,2] = poisson_rng(theta_prev[n,2]);
        diff_y_prev[n] = y_prev[n,1] - y_prev[n,2];
      }
}
