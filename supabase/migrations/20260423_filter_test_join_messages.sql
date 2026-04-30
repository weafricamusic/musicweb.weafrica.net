-- Filter out test/internal user join messages from battle_comments
-- This prevents fake "post3000-host-XXXX joined" messages from appearing in consumer views
--
-- The fn_battle_presence_join_message() function creates a join message for every
-- battle_presence insert. We need to filter out messages from test/internal users
-- whose user_ids contain patterns like 'post3000', 'port3000', 'phase2', 'verify', etc.

-- Drop the existing trigger
DROP TRIGGER IF EXISTS trg_battle_presence_join_message ON public.battle_presence;

-- Recreate the function with test user filtering
CREATE OR REPLACE FUNCTION public.fn_battle_presence_join_message()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  test_patterns TEXT[] := ARRAY[
    'post3000', 'port3000', 'phase2', 'verify',
    'localhost', 'test_', '_test', 'example.com'
  ];
  user_id_lower TEXT;
  pattern TEXT;
BEGIN
  -- Normalize user_id for pattern matching
  user_id_lower := LOWER(COALESCE(NEW.user_id, ''));
  
  -- Check if user_id contains any test patterns
  FOREACH pattern IN ARRAY test_patterns LOOP
    IF user_id_lower LIKE '%' || pattern || '%' THEN
      -- This is a test user, skip creating join message
      RETURN NEW;
    END IF;
  END LOOP;
  
  -- Also skip if user_id is empty or looks like a system placeholder
  IF user_id_lower IN ('', 'null', 'undefined', 'guest', 'anonymous') THEN
    RETURN NEW;
  END IF;
  
  -- Create join message for real users only
  INSERT INTO public.battle_comments (battle_id, user_id, message, is_system, created_at)
  VALUES (NEW.battle_id, NEW.user_id, COALESCE(NEW.user_id, 'Someone') || ' joined', true, NOW());
  
  RETURN NEW;
END;
$$;

-- Recreate the trigger
CREATE TRIGGER trg_battle_presence_join_message
AFTER INSERT ON public.battle_presence
FOR EACH ROW
EXECUTE FUNCTION public.fn_battle_presence_join_message();

-- Clean up existing test join messages from battle_comments
-- This removes messages where the user_id contains test patterns
DELETE FROM public.battle_comments 
WHERE is_system = true 
  AND (
    LOWER(user_id) LIKE '%post3000%' 
    OR LOWER(user_id) LIKE '%port3000%' 
    OR LOWER(user_id) LIKE '%phase2%' 
    OR LOWER(user_id) LIKE '%verify%'
    OR LOWER(user_id) LIKE '%localhost%'
    OR LOWER(user_id) LIKE '%test_%'
    OR LOWER(user_id) LIKE '%_test%'
    OR LOWER(user_id) LIKE '%example.com%'
    OR LOWER(message) LIKE '%post3000%'
    OR LOWER(message) LIKE '%port3000%'
    OR LOWER(message) LIKE '%phase2%'
    OR LOWER(message) LIKE '%verify%'
  );