(function(){
    /**
    DEPENDENCIES
    */

    var draw = require('lib/draw');
    var console = require('lib/console');

    /**
    HELPERS
    */

    function INT(x)
    {
        if ($ir_is_float64(x))
            return $ir_f64_to_i32(x);
        else
            return x;
    }

    /**
    SETTINGS
    */
    var COURT_WIDTH = 950;
    var COURT_HEIGHT = 500;
    var NET_X = INT(COURT_WIDTH / 2 - 2);
    var SCORE1_X = INT(COURT_WIDTH / 4 - 20);
    var SCORE2_X = INT(COURT_WIDTH / 2 + COURT_WIDTH / 4 - 20);
    var NET_HEIGHT = INT(COURT_HEIGHT / 20);
    var NET_NUM = 10;
    var NET_Y_START = 50 + INT(NET_HEIGHT / 2);
    var PADDLE_HEIGHT = 100;
    var PADDLE_Y_START = INT(COURT_HEIGHT / 2 - PADDLE_HEIGHT / 2 + 50);
    var PADDLE_MAX_Y = INT(COURT_HEIGHT - PADDLE_HEIGHT / 2);
    var PADDLE_MIN_Y = 50;
    var PLAYER1_X = 10;
    var PLAYER2_X = INT(COURT_WIDTH - 20);
    var BALL_SIZE = 20;
    var BALL_X_START = INT(COURT_WIDTH / 2 - BALL_SIZE / 2);
    var BALL_Y_START = INT(COURT_HEIGHT / 2 - BALL_SIZE / 2 + 50);
    var PAUSE_MSG = "PRESS S KEY";
    var PAUSE_MSG_X = INT(COURT_WIDTH / 2 - ((PAUSE_MSG.length + 3) * 20) / 2);
    var PAUSE_MSG_Y = INT(COURT_HEIGHT / 2);

    /**
    GAME OBJECTS
    */

    // Canvas Window
    var window = draw.Window(50, 50, COURT_WIDTH, COURT_HEIGHT + 50, "Ping Pong");
    // If the game is started
    var stopped = true;

    // Canvas setup
    window.canvas.setFont("helvetica");

    // Ball State
    var ball = {
        x : 0,
        y : 0,
        x_d : 0,
        y_d : 0
    };

    // generic player
    var player = {
        score : 0,
        x : 0,
        y : PADDLE_Y_START,
        y_d : 0
    };

    // players
    var player1 = Object.create(player);
    player1.x = PLAYER1_X;

    var player2 = Object.create(player);
    player2.x = PLAYER2_X;

    // computer state
    var computer_move_d = 0;

    function gameInit()
    {
        ball = {
            x : BALL_X_START,
            y : BALL_Y_START,
            // TODO: when computer is better, make serve random
            //x_d : (Math.floor( Math.random() * 2 ) == 1) ? 1 : -1,
            x_d : 1,
            y_d : 0
        };

        player1.y = PADDLE_Y_START;
        player1.y_d = 0;
        player2.y = PADDLE_Y_START;
        player2.y_d = 0;

        computer_move_d = (Math.floor( Math.random() * 2 ) == 1) ? 1 : -1;

    }

    /**
    RENDERING
    */
    window.onRender(function(canvas)
    {
        var i = 0;
        var y = 0;

        // setup
        canvas.clear("#181818");

        canvas.setColor("#FFFFFF");

        // scores
        canvas.drawText(SCORE1_X, 40, player1.score.toString());
        canvas.drawText(SCORE2_X, 40, player2.score.toString());



        // upper boundery
        canvas.fillRect(0, 45, COURT_WIDTH, 5);

        // net
        i = NET_NUM;
        y = NET_Y_START;
        while (i--)
        {
            canvas.fillRect(NET_X, y, 2, NET_HEIGHT);
            y += NET_HEIGHT + NET_HEIGHT;
        }

        // paddles
        canvas.fillRect(player1.x, player1.y, 10, PADDLE_HEIGHT);
        canvas.fillRect(player2.x, player2.y, 10, PADDLE_HEIGHT);

        // ball
        canvas.fillRect(ball.x, ball.y, BALL_SIZE, BALL_SIZE);

        // GAME STATE

        if (stopped)
        {
            canvas.setColor("#6F847F");
            canvas.drawText(PAUSE_MSG_X, PAUSE_MSG_Y, PAUSE_MSG);
            return;
        }

        // check for ball hitting ends (score)

        if (ball.x >= COURT_WIDTH - BALL_SIZE)
        {
            player1.score += 1;
            stopped = true;
            gameInit();
        } else if (ball.x <= 0)
        {
            player2.score += 1;
            stopped = true;
            gameInit();
        }

        // detect ball hitting sides
        if (ball.y <= 50)
        {
            ball.y_d = 1;
        } else if (ball.y >= COURT_HEIGHT - BALL_SIZE + 50)
        {
            ball.y_d = -1;
        }

        // detect ball hitting paddles
        if (ball.x === player2.x - BALL_SIZE)
        {
            // TODO: overlap?
            if (ball.y >= player2.y - 10 && (ball.y <= player2.y + PADDLE_HEIGHT - BALL_SIZE + 10))
            {
                ball.x_d = -1;
                ball.y_d = player2.y_d;
            }
        }

        if (ball.x === player1.x)
        {
            // TODO: overlap?
            if (ball.y >= player1.y - 10  && (ball.y <= player1.y + PADDLE_HEIGHT - BALL_SIZE + 10))
            {
                ball.x_d = 1;
                ball.y_d = player2.y_d;
            }
        }

        // update ball position

        ball.x += 5 * ball.x_d;
        ball.y += 5 * ball.y_d;

        // computer player
        // TODO: replace with something better
        player1.y += 5 * computer_move_d;
        if (player1.y <= PADDLE_MIN_Y + 30)
            computer_move_d = 1;
        else if (player1.y >= PADDLE_MAX_Y - 30)
            computer_move_d = -1;

    });

    /**
    INPUT
    */
    window.onKeypress(function(canvas, key)
    {
        // handle player movements
        if (player2.y < PADDLE_MAX_Y && key === "Down")
        {
            player2.y += 20;
            player2.y_d = 1;
        }
        else if (player2.y > PADDLE_MIN_Y && key === "Up")
        {
            player2.y -= 20;
            player2.y_d = -1;
        }
        else if (key === "s")
        {
            stopped = !stopped;
        }
        else if (key === "r")
        {
            stopped = true;
            gameInit();
        }
    });

    /**
    START
    */
    gameInit();
    window.show();

})();
