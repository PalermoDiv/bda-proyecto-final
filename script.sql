DELIMITER $$
CREATE PROCEDURE actualizarAlumno(IN p_matricula INT, IN p_nombre VARCHAR(100),
 IN p_grado VARCHAR(50), OUT p_ok INT, OUT p_msg VARCHAR(150))
BEGIN
  IF p_matricula IS NULL OR p_nombre IS NULL OR p_grado IS NULL
    OR p_nombre = '' OR p_grado = '' THEN 
    SET p_ok = 0;
    SET p_msg = 'Datos incompletos';
  ELSEIF NOT EXISTS(SELECT 1 FROM Alumnos WHERE matricula = p_matricula) THEN 
    SET p_ok = 0;
    SET p_msg = 'La matricula ya existe'
  ELSE 
    UPDATE Alumnos SET nombre = p_nombre, grado = p_grado WHERE matricula=p_matricula;
    SET p_ok = 1;
    SET p_msg = 'Datos actualizados correctamente';
  END IF;
END $$
DELIMITER ;

CALL actualizarAlumno(1011,'Utadas Hikarus','1 secundaria',@ok,@msg);
SELECT @ok AS ok, @msg as msg;
