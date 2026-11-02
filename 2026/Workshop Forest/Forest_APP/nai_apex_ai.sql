create or replace package nai_apex_ai authid definer as
  procedure ajax(p_operation varchar2, p_mode varchar2, p_profile varchar2,
                 p_team varchar2, p_action varchar2, p_prompt varchar2);
end nai_apex_ai;
/